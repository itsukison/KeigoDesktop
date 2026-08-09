// Shared plumbing for the three billing Edge Functions.
//
// One module rather than three copies: `desktop-checkout`, `desktop-portal` and
// `desktop-stripe-webhook` all talk to the same Stripe account at the same pinned
// API version and reach the same `public.desktop_*` entry points. Three copies of
// the version pin is three places for it to drift, and `docs/billing.md` §2 spends a
// section on why an API-version disagreement is the specific bug this design cannot
// tolerate.

// ---------------------------------------------------------------------------
// API version — pinned, never inherited (§2)
// ---------------------------------------------------------------------------
//
// Three reasons this is not optional:
//
//   - `billing_mode: flexible` in Checkout requires >= 2025-06-30.basil.
//   - `current_period_start/end` moved off the subscription object onto the
//     subscription ITEM in 2025-03-31.basil. Reading `sub.current_period_end` on a
//     newer version returns undefined and writes a null period, which silently
//     breaks the 解約予定 display and the reconciliation priority in §5.
//   - A webhook endpoint keeps the version it was created with, indefinitely. The
//     dead PromptOS endpoint was on 2026-01-28.clover. This is also why nothing in
//     `desktop-stripe-webhook` reads a field off the payload except the customer id:
//     the payload's shape is the endpoint's version, and the fetch's shape is ours.
//
// **The webhook endpoint in the Dashboard must be created on this same version.**
export const STRIPE_API_VERSION = "2026-07-29.dahlia";

const STRIPE_API = "https://api.stripe.com";

/** The only two prices we sell. Resolved to a price id SERVER-side (§7). */
export const PRICE_LOOKUP_KEYS = ["pro_monthly_jpy", "pro_yearly_jpy"] as const;
export type PriceLookupKey = typeof PRICE_LOOKUP_KEYS[number];

export const SITE_URL = Deno.env.get("DESKTOP_BILLING_SITE_URL") ?? "https://keigobutton.com";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function jsonError(code: string, message: string, status: number): Response {
  return json({ error: { code, message } }, status);
}

/// The gateway validated the signature (`verify_jwt = true`); this only reads the
/// claim. Same posture as `desktop-rewrite`.
export function claimsFromAuthHeader(header: string): { sub: string; email?: string } | null {
  const token = header.replace(/^Bearer\s+/i, "");
  const segments = token.split(".");
  if (segments.length < 2) return null;
  try {
    const padded = segments[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(padded + "=".repeat((4 - padded.length % 4) % 4)));
    if (typeof payload?.sub !== "string") return null;
    return {
      sub: payload.sub,
      email: typeof payload.email === "string" ? payload.email : undefined,
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Stripe
// ---------------------------------------------------------------------------

export class StripeError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string | null,
    message: string,
  ) {
    super(message);
    this.name = "StripeError";
  }
}

/// Stripe's form encoding, including the bracket syntax for nested objects and
/// arrays: `line_items[0][price]`, `expand[0]`. Values that are `undefined` or
/// `null` are dropped rather than sent as the string "null", which Stripe would
/// take literally.
export function formEncode(input: Record<string, unknown>, prefix = ""): string[] {
  const parts: string[] = [];
  for (const [rawKey, value] of Object.entries(input)) {
    if (value === undefined || value === null) continue;
    const key = prefix ? `${prefix}[${rawKey}]` : rawKey;
    if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (item && typeof item === "object") {
          parts.push(...formEncode(item as Record<string, unknown>, `${key}[${index}]`));
        } else if (item !== undefined && item !== null) {
          parts.push(`${encodeURIComponent(`${key}[${index}]`)}=${encodeURIComponent(String(item))}`);
        }
      });
    } else if (typeof value === "object") {
      parts.push(...formEncode(value as Record<string, unknown>, key));
    } else {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
    }
  }
  return parts;
}

export async function stripe(
  path: string,
  options: {
    method?: "GET" | "POST" | "DELETE";
    body?: Record<string, unknown>;
    query?: Record<string, unknown>;
    idempotencyKey?: string;
  } = {},
): Promise<any> {
  const secret = Deno.env.get("STRIPE_SECRET_KEY");
  if (!secret) throw new StripeError(500, "configuration_missing", "STRIPE_SECRET_KEY is not set");

  const method = options.method ?? "GET";
  const query = options.query ? formEncode(options.query).join("&") : "";
  const url = `${STRIPE_API}${path}${query ? `?${query}` : ""}`;

  const headers: Record<string, string> = {
    Authorization: `Bearer ${secret}`,
    "Stripe-Version": STRIPE_API_VERSION,
  };
  if (options.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;
  let body: string | undefined;
  if (options.body) {
    headers["Content-Type"] = "application/x-www-form-urlencoded";
    body = formEncode(options.body).join("&");
  }

  const res = await fetch(url, { method, headers, body });
  const text = await res.text();
  let parsed: any = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    // fall through — a non-JSON body from Stripe is already an error
  }
  if (!res.ok) {
    throw new StripeError(
      res.status,
      parsed?.error?.code ?? parsed?.error?.type ?? null,
      parsed?.error?.message ?? text.slice(0, 300),
    );
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Postgres, through the `public.desktop_*` entry points
// ---------------------------------------------------------------------------

/// No `desktop` table is reachable over the API — the schema is deliberately not in
/// the project's exposed-schema list, because widening it would change the API
/// surface of a project the shipped iOS keyboard also lives behind (AGENTS.md §6).
/// Everything goes through a SECURITY DEFINER function in `public`.
export async function desktopRPC(fn: string, args: Record<string, unknown>): Promise<any> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set");

  const res = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn}: ${res.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

/// `returns table (…)` comes back as an array of one row.
export async function desktopRPCRow(fn: string, args: Record<string, unknown>): Promise<any> {
  const rows = await desktopRPC(fn, args);
  return Array.isArray(rows) ? rows[0] ?? null : rows;
}

// ---------------------------------------------------------------------------
// §3.2 — which subscription is OURS
// ---------------------------------------------------------------------------

export type SelectedSubscription = {
  id: string;
  productId: string | null;
  priceId: string | null;
  priceLookupKey: string | null;
  interval: string | null;
  status: string;
  currentPeriodStart: string | null;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  cancelAt: string | null;
  scheduleId: string | null;
};

/// Statuses that mean the subscription is still a live object, in the order a tie
/// should be broken. `canceled` is terminal and immutable, so a canceled row only
/// wins when it is all there is.
const LIVE_STATUSES = new Set([
  "active",
  "trialing",
  "past_due",
  "incomplete",
  "unpaid",
  "paused",
]);

function toISO(seconds: unknown): string | null {
  return typeof seconds === "number" ? new Date(seconds * 1000).toISOString() : null;
}

/// Picks the subscription this product owns, per §3.2's three conditions.
///
/// Product membership is validated AGAIN in SQL (`desktop.pro_products`) — this
/// function only has to CHOOSE, and it deliberately does not filter on status:
/// `canceled` and `unpaid` have to reach the reconciler too, or the row would keep
/// reporting the last status that happened to qualify.
///
/// The period is read off `items.data[0]`, never off the subscription. As of
/// 2025-03-31.basil `sub.current_period_end` is undefined; they moved because a
/// subscription can hold mixed intervals. Ours never will — one item, one price.
export function selectSubscription(
  subscriptions: any[],
  proProductIds: Set<string>,
): { selected: SelectedSubscription | null; duplicates: number } {
  const candidates = subscriptions.filter((sub) => {
    const items = sub?.items?.data ?? [];
    if (items.length !== 1) return false;
    const price = items[0]?.price;
    const product = typeof price?.product === "string" ? price.product : price?.product?.id;
    if (!product || !proProductIds.has(product)) return false;
    const interval = price?.recurring?.interval;
    return interval === "month" || interval === "year";
  });

  if (candidates.length === 0) return { selected: null, duplicates: 0 };

  const live = candidates.filter((sub) => LIVE_STATUSES.has(sub.status));
  const pool = live.length > 0 ? live : candidates;
  // Latest `created` wins. Never summed, never picked arbitrarily (§3.2).
  const winner = pool.reduce((a, b) => ((b.created ?? 0) > (a.created ?? 0) ? b : a));

  const item = winner.items.data[0];
  const price = item.price;
  const product = typeof price.product === "string" ? price.product : price.product?.id;

  return {
    duplicates: live.length > 1 ? live.length : 0,
    selected: {
      id: winner.id,
      productId: product ?? null,
      priceId: price?.id ?? null,
      priceLookupKey: price?.lookup_key ?? null,
      interval: price?.recurring?.interval ?? null,
      status: winner.status,
      currentPeriodStart: toISO(item.current_period_start),
      currentPeriodEnd: toISO(item.current_period_end),
      // Display state, never entitlement. A subscription scheduled to cancel is
      // `active` until it is not (§3.1).
      cancelAtPeriodEnd: winner.cancel_at_period_end === true,
      cancelAt: toISO(winner.cancel_at),
      scheduleId: typeof winner.schedule === "string" ? winner.schedule : winner.schedule?.id ?? null,
    },
  };
}

/// The allowlist, read from the one place that owns it. Cached for the isolate's
/// lifetime: it changes only when a product is replaced, which is a deploy-scale
/// event, and re-reading it on every webhook would be a round trip per event.
let proProductCache: Set<string> | null = null;

export async function proProductIds(): Promise<Set<string>> {
  if (proProductCache) return proProductCache;
  const rows = await desktopRPC("desktop_pro_product_ids", {});
  const ids = (Array.isArray(rows) ? rows : []).map((row: any) =>
    typeof row === "string" ? row : row?.stripe_product_id
  ).filter(Boolean);
  proProductCache = new Set(ids);
  return proProductCache;
}
