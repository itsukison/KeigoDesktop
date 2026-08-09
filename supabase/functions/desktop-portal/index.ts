// desktop-portal
//
// One call, no interstitial. `docs/billing.md` §10: 「いつでもワンクリックで解約」 is
// defensible only while it is literally true, and the 消費者庁 検討会 names
// 「解約前に他のプラン等の選択肢を紹介し、消費者を引き留めようとする」 as a candidate
// prohibited practice. So there is no confirmation step of our own here, and the
// portal's retention offer must stay OFF in the Dashboard (§11 step 1b).
//
// The portal is also where cancellation, card updates and invoices live, which is
// why the `past_due` banner and the 解約予定 row in the app both point at it.
//
// ---------------------------------------------------------------------------
// DEEP LINKS (`flow`).
//
// A single 「お支払い管理」 button dropped the user on the portal's overview and left
// them to find the action themselves — the reason cancellation, the annual switch and
// un-cancelling all felt missing when they were merely two clicks in. `flow_data`
// opens the portal ON the requested screen instead.
//
// The flows we expose and why each is the one Stripe provides:
//
//   cancel          → `subscription_cancel`. Note this makes 解約 FEWER clicks, not
//                     more, so §10's 「ワンクリックで解約」 claim gets stronger. The
//                     `retention` field is deliberately never sent: an offer shown
//                     while someone is cancelling is exactly the 引き留め practice
//                     the 消費者庁 検討会 named.
//   update          → `subscription_update`. The monthly ↔ annual switch. Requires
//                     `subscription_update.products` on the portal CONFIGURATION —
//                     with the feature enabled but no products listed, the screen
//                     opens with nothing to switch to.
//   payment_method  → `payment_method_update`. Where the `past_due` banner points.
//
// There is no flow for UN-cancelling: Stripe has no `subscription_renew` type, and
// the overview already carries the renew button once a cancellation is scheduled. So
// 解約を取り消す sends no `flow` and lands on the overview, which is the shortest
// path Stripe offers.
//
// `flow` is validated against a fixed allowlist. §7's rule is that the client names
// an intent, never a Stripe object — the subscription id is looked up server-side
// from the caller's own row, so no request can address someone else's subscription.

import {
  claimsFromAuthHeader,
  corsHeaders,
  desktopRPCRow,
  json,
  jsonError,
  SITE_URL,
  stripe,
  StripeError,
} from "../_shared/billing.ts";

const FLOWS = ["cancel", "update", "payment_method"] as const;
type Flow = typeof FLOWS[number];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonError("method_not_allowed", "Use POST.", 405);

  const claims = claimsFromAuthHeader(req.headers.get("Authorization") ?? "");
  if (!claims) return jsonError("unauthorized", "サインインしてください。", 401);

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    // An absent body is the plain-overview case, which is a valid request.
  }

  const flow = FLOWS.includes(body?.flow) ? (body.flow as Flow) : null;

  try {
    const state = await desktopRPCRow("desktop_billing_state", { p_user_id: claims.sub });

    // No Stripe customer means the user has never started a checkout. There is
    // nothing to manage, and creating a customer just to open an empty portal would
    // put a billing record on an account that has never paid.
    if (!state?.stripe_customer_id) {
      return jsonError("no_billing_account", "お支払い情報がまだありません。", 404);
    }

    const session = await stripe("/v1/billing_portal/sessions", {
      method: "POST",
      body: {
        customer: state.stripe_customer_id,
        return_url: `${SITE_URL}/billing/return`,
        locale: "ja",
        // `undefined` is dropped by the encoder, so an unrecognised or absent
        // `flow` degrades to the plain overview rather than erroring. That matters
        // more than it looks: an app build newer than this function would otherwise
        // turn every billing button into a 502.
        flow_data: flowData(flow, state.stripe_subscription_id),
      },
    });

    return json({ url: session.url, flow });
  } catch (error) {
    const stripeError = error instanceof StripeError ? error : null;
    console.error(JSON.stringify({
      event: "desktop_portal",
      userId: claims.sub,
      status: stripeError ? "stripe_error" : "error",
      code: stripeError?.code,
      message: error instanceof Error ? error.message : "unknown",
    }));
    return jsonError("portal_failed", "お支払い管理を開けませんでした。", 502);
  }
});

/// The `flow_data` body for a requested flow, or `undefined` for the overview.
///
/// `cancel` and `update` both address a specific subscription and Stripe rejects the
/// flow without one. A user whose row has no subscription id — never subscribed, or
/// already fully cancelled — therefore falls back to the overview rather than getting
/// a 502 for asking a question that no longer applies to them.
function flowData(
  flow: Flow | null,
  subscriptionId: string | null | undefined,
): Record<string, unknown> | undefined {
  if (flow === "payment_method") return { type: "payment_method_update" };
  if (!subscriptionId) return undefined;
  if (flow === "cancel") {
    // No `retention` key. See the header — an offer surfaced mid-cancellation is
    // the practice §10 refuses to adopt, and omitting it is how that stays true.
    return { type: "subscription_cancel", subscription: subscriptionId };
  }
  if (flow === "update") {
    return { type: "subscription_update", subscription: subscriptionId };
  }
  return undefined;
}
