// desktop-stripe-webhook
//
// `verify_jwt = false` — Stripe does not send a Supabase JWT. The signature check
// below IS the authentication, and it is the only thing standing between the public
// internet and "rewrite anyone's entitlement". Do not relax it.
//
// `docs/billing.md` §5 is the design. The one property everything else rests on:
//
//   **The payload is a notification, not a source of truth.** It is read for exactly
//   one thing — the customer id — and every field that decides anything comes from a
//   fresh `GET /v1/subscriptions` against the pinned API version. That is Stripe's
//   own advice ("This data might already be stale by the time you process it"), and
//   it is also what makes the endpoint's own API version harmless: an endpoint keeps
//   the version it was created with forever, and a handler that reads
//   `sub.current_period_end` off the payload would silently write nulls the day
//   those fields moved.
//
// All nine subscribed events run this same path, so there are not nine chances to
// write a stale state.
//
// ONE DEVIATION FROM §5, and §5 names it as the sanctioned alternative. §5's handler
// holds the per-customer advisory lock ACROSS the Stripe fetch. Over PostgREST each
// RPC is its own transaction and the fetch happens here, between them, so this is
// fetch-then-lock: `desktop_now()` is stamped AFTER the fetch and the monotonic
// `reconciled_at` guard discards the older snapshot. What is NOT relaxed is the
// ordering §5 calls load-bearing — `desktop_process_stripe_event` marks the event
// processed in the SAME transaction that writes the row, so a mid-handler failure
// leaves it unprocessed and Stripe retries within its 3-day envelope.

import {
  desktopRPC,
  desktopRPCRow,
  proProductIds,
  selectSubscription,
  stripe,
  welcomeCouponId,
} from "../_shared/billing.ts";

/// Stripe's default tolerance. NEVER 0: that would reject every event whose delivery
/// took longer than the clocks disagree by.
const TOLERANCE_SECONDS = 300;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST.", { status: 405 });

  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) {
    console.error(JSON.stringify({ event: "desktop_webhook", status: "no_signing_secret" }));
    return new Response("misconfigured", { status: 500 });
  }

  // The RAW body. Re-serializing parsed JSON changes key order and whitespace and
  // the HMAC no longer matches.
  const raw = await req.text();
  const signature = req.headers.get("stripe-signature") ?? "";

  if (!(await verifySignature(raw, signature, secret))) {
    console.warn(JSON.stringify({ event: "desktop_webhook", status: "bad_signature" }));
    return new Response("invalid signature", { status: 400 });
  }

  let event: any;
  try {
    event = JSON.parse(raw);
  } catch {
    return new Response("invalid json", { status: 400 });
  }

  try {
    await handle(event);
    return new Response("ok", { status: 200 });
  } catch (error) {
    console.error(JSON.stringify({
      event: "desktop_webhook",
      stripeEventId: event?.id,
      type: event?.type,
      status: "error",
      message: error instanceof Error ? error.message : "unknown",
    }));
    // 5xx so Stripe retries. Anything that failed above left the event unprocessed.
    return new Response("retry", { status: 500 });
  }
});

// ---------------------------------------------------------------------------
// Signature — HMAC-SHA256 over "{timestamp}.{raw_body}"
// ---------------------------------------------------------------------------

async function verifySignature(raw: string, header: string, secret: string): Promise<boolean> {
  const parts = new Map<string, string[]>();
  for (const segment of header.split(",")) {
    const index = segment.indexOf("=");
    if (index < 0) continue;
    const key = segment.slice(0, index).trim();
    const value = segment.slice(index + 1).trim();
    parts.set(key, [...(parts.get(key) ?? []), value]);
  }

  const timestamp = parts.get("t")?.[0];
  // **Only `v1`.** Stripe's own guidance is to ignore all other schemes "to prevent
  // downgrade attacks" — accepting a future v0-style scheme because it is present in
  // the header is the whole of that attack.
  const signatures = parts.get("v1") ?? [];
  if (!timestamp || signatures.length === 0) return false;

  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (!Number.isFinite(age) || age > TOLERANCE_SECONDS) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${raw}`),
  );
  const expected = [...new Uint8Array(mac)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return signatures.some((candidate) => constantTimeEquals(candidate, expected));
}

/// Constant time in the length-equal case, which is the only case that carries
/// information here — both sides are fixed-width hex.
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------
// The handler
// ---------------------------------------------------------------------------

async function handle(event: any): Promise<void> {
  const eventId: string = event.id;
  const type: string = event.type;
  const object = event?.data?.object ?? {};

  // Cheap early-out. An optimisation only — `desktop_process_stripe_event` re-checks
  // under the row it inserts, and that is the check that counts.
  if (await desktopRPC("desktop_stripe_event_processed", { p_event_id: eventId })) {
    return;
  }

  // §3.3: an expired Checkout Session releases the intent lock. There is no
  // subscription state to reconcile, so the event is recorded and nothing is written.
  if (type === "checkout.session.expired") {
    await desktopRPC("desktop_clear_checkout_intent", {
      p_user_id: null,
      p_session_id: typeof object.id === "string" ? object.id : null,
    });
    await desktopRPCRow("desktop_process_stripe_event", {
      p_event_id: eventId,
      p_event_type: type,
      p_reconciled_at: await desktopRPC("desktop_now", {}),
      p_reconcile: false,
    });
    return;
  }

  if (type === "checkout.session.completed" || type === "checkout.session.async_payment_succeeded") {
    await desktopRPC("desktop_clear_checkout_intent", {
      p_user_id: null,
      p_session_id: typeof object.id === "string" ? object.id : null,
    });
  }

  // Step 3 — the ONLY thing the payload is used for.
  const customerId = typeof object.customer === "string"
    ? object.customer
    : typeof object.customer?.id === "string"
    ? object.customer.id
    : null;

  if (!customerId) {
    // A dispute or a charge with no customer attached. Nothing of ours to reconcile,
    // but it must not be silent (§8).
    await desktopRPC("desktop_raise_billing_alert", {
      p_kind: "billing_needs_review",
      p_stripe_customer_id: null,
      p_user_id: null,
      p_payload: { reason: "no_customer_on_event", event_id: eventId, type },
    });
    await desktopRPCRow("desktop_process_stripe_event", {
      p_event_id: eventId,
      p_event_type: type,
      p_reconciled_at: await desktopRPC("desktop_now", {}),
      p_reconcile: false,
    });
    return;
  }

  // Resolve the user. The mapping normally already exists — `desktop-checkout` wrote
  // it before Stripe was ever called — but a Dashboard-created subscription has
  // never been through that path, so two fallbacks: the session's
  // `client_reference_id` and the customer's own metadata.
  let userId: string | null = await desktopRPC("desktop_user_for_stripe_customer", {
    p_stripe_customer_id: customerId,
  });
  if (!userId) userId = await userFromStripe(object, customerId);

  if (!userId) {
    await desktopRPC("desktop_raise_billing_alert", {
      p_kind: "billing_needs_review",
      p_stripe_customer_id: customerId,
      p_user_id: null,
      p_payload: { reason: "no_user_for_customer", event_id: eventId, type },
    });
    await desktopRPCRow("desktop_process_stripe_event", {
      p_event_id: eventId,
      p_event_type: type,
      p_reconciled_at: await desktopRPC("desktop_now", {}),
      p_reconcile: false,
    });
    return;
  }

  // §8 — a FULL refund of the current period cancels immediately and revokes; a
  // partial one is not a statement about access. Done BEFORE the fetch below so the
  // reconciliation that follows already sees the cancelled state, rather than
  // writing `active` and being corrected by a second event.
  if (type === "charge.refunded") {
    await applyRefundPolicy(object, customerId, eventId);
  }

  // Step 7 — the fetch. Everything that decides anything comes from here.
  const subscriptions = await stripe("/v1/subscriptions", {
    query: {
      customer: customerId,
      status: "all",
      limit: 100,
      // `discounts` is expandable and comes back as bare ids otherwise, which would
      // make every subscription look undiscounted and the welcome-offer stamp never
      // fire. The coupon id is one level below the discount, hence the deeper path.
      expand: ["data.items.data.price", "data.discounts.coupon"],
    },
  });

  const { selected, duplicates } = selectSubscription(
    subscriptions?.data ?? [],
    await proProductIds(),
  );

  if (duplicates > 1) {
    // §3.2: latest `created` wins AND an alert is raised. Never summed, never picked
    // arbitrarily, and never silently.
    await desktopRPC("desktop_raise_billing_alert", {
      p_kind: "duplicate_subscription",
      p_stripe_customer_id: customerId,
      p_user_id: userId,
      p_payload: { count: duplicates, chosen: selected?.id, event_id: eventId },
    });
  }

  // §8's "money arrives after the subscription is gone". The reconciler is about to
  // correctly leave this user `free`, which is the right entitlement and the wrong
  // outcome, because money was received. A human decides: restore or refund.
  if (type === "invoice.paid" && !selected) {
    await desktopRPC("desktop_raise_billing_alert", {
      p_kind: "billing_needs_review",
      p_stripe_customer_id: customerId,
      p_user_id: userId,
      p_payload: {
        reason: "payment_without_subscription",
        event_id: eventId,
        invoice: object.id,
        amount_paid: object.amount_paid,
        currency: object.currency,
      },
    });
  }

  // Step 6, moved after the fetch — the Postgres clock, stamped once the data it is
  // guarding actually exists. Taking it before the fetch would let a racing handler
  // discard the fresher snapshot.
  const reconciledAt = await desktopRPC("desktop_now", {});

  const result = await desktopRPCRow("desktop_process_stripe_event", {
    p_event_id: eventId,
    p_event_type: type,
    p_reconciled_at: reconciledAt,
    p_reconcile: true,
    p_stripe_customer_id: customerId,
    p_user_id: userId,
    p_stripe_subscription_id: selected?.id ?? null,
    p_stripe_product_id: selected?.productId ?? null,
    p_stripe_price_id: selected?.priceId ?? null,
    p_price_lookup_key: selected?.priceLookupKey ?? null,
    p_interval: selected?.interval ?? null,
    p_status: selected?.status ?? null,
    p_current_period_start: selected?.currentPeriodStart ?? null,
    p_current_period_end: selected?.currentPeriodEnd ?? null,
    p_cancel_at_period_end: selected?.cancelAtPeriodEnd ?? false,
    p_cancel_at: selected?.cancelAt ?? null,
    p_schedule_id: selected?.scheduleId ?? null,
    p_currency: selected?.currency ?? null,
  });

  // The welcome offer's redemption stamp.
  //
  // **Reporting only.** Eligibility was already settled when the session was created,
  // and it was settled by the row EXISTING rather than by this field — so a failure
  // here cannot let anyone claim a second discount, and it deliberately does not run
  // inside `desktop_process_stripe_event`'s transaction. What it buys is the ability
  // to answer "was this subscriber won by the offer", which nothing else records:
  // the coupon is on the Stripe subscription, not on ours.
  //
  // The RPC itself is first-write-wins, so the repeated `invoice.paid` events over a
  // discounted subscription's life do not move the date.
  const welcomeCoupons = new Set(
    [welcomeCouponId("month"), welcomeCouponId("year")].filter((id): id is string => id !== null),
  );
  const redeemed = selected?.discountCouponIds.find((id) => welcomeCoupons.has(id)) ?? null;
  if (redeemed && userId) {
    await desktopRPC("desktop_mark_welcome_offer_redeemed", {
      p_user_id: userId,
      p_coupon_id: redeemed,
      p_currency: selected?.currency ?? null,
    }).catch(() => {});
  }

  console.log(JSON.stringify({
    event: "desktop_webhook",
    stripeEventId: eventId,
    type,
    userId,
    subscriptionId: selected?.id ?? null,
    stripeStatus: selected?.status ?? null,
    currency: selected?.currency ?? null,
    welcomeCoupon: redeemed,
    plan: result?.plan ?? null,
    duplicate: result?.duplicate === true,
    applied: result?.applied === true,
    status: "ok",
  }));
}

/// Two fallbacks for a subscription that never went through `desktop-checkout`.
async function userFromStripe(object: any, customerId: string): Promise<string | null> {
  if (typeof object.client_reference_id === "string" && object.client_reference_id) {
    return object.client_reference_id;
  }
  try {
    const customer = await stripe(`/v1/customers/${customerId}`);
    const id = customer?.metadata?.supabase_user_id;
    return typeof id === "string" && id ? id : null;
  } catch {
    return null;
  }
}

/// §8's refund table, and the reason `charge.refunded` is a subscribed event rather
/// than merely an accounting concern: a refund issued BY HAND in the Dashboard has
/// to reconcile, not diverge.
///
/// Full refund of the current period → cancel immediately and revoke. Partial →
/// unchanged, because goodwill and proration adjustments are not a statement about
/// access. Quota is never clawed back either way: rewrites already delivered were
/// delivered, and the window simply ends with the entitlement.
async function applyRefundPolicy(
  charge: any,
  customerId: string,
  eventId: string,
): Promise<void> {
  const amount = Number(charge?.amount ?? 0);
  const refunded = Number(charge?.amount_refunded ?? 0);
  if (!amount || refunded < amount) return;

  const invoiceId = typeof charge.invoice === "string" ? charge.invoice : charge.invoice?.id;
  if (!invoiceId) return;

  try {
    const invoice = await stripe(`/v1/invoices/${invoiceId}`);
    const subscriptionId = typeof invoice?.subscription === "string"
      ? invoice.subscription
      : invoice?.parent?.subscription_details?.subscription ?? null;
    if (!subscriptionId) return;

    await stripe(`/v1/subscriptions/${subscriptionId}`, { method: "DELETE" });

    console.log(JSON.stringify({
      event: "desktop_webhook_refund",
      stripeEventId: eventId,
      customerId,
      subscriptionId,
      action: "cancelled_immediately",
    }));
  } catch (error) {
    // The refund is real whatever happens next, so this never swallows silently: a
    // human has to see that a full refund did not revoke.
    await desktopRPC("desktop_raise_billing_alert", {
      p_kind: "billing_needs_review",
      p_stripe_customer_id: customerId,
      p_user_id: null,
      p_payload: {
        reason: "refund_cancel_failed",
        event_id: eventId,
        message: error instanceof Error ? error.message : "unknown",
      },
    });
  }
}
