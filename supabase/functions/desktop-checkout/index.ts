// desktop-checkout
//
// Opens a Stripe Checkout Session for 敬語ボタン Pro and hands the URL back to the
// Mac app, which opens it in the DEFAULT BROWSER rather than a web view — Apple Pay
// needs Safari's payment sheet.
//
// `docs/billing.md` §3.3 is the whole of this file. Four defences against the naive
// "is there an active subscription?" check, in the order they fire:
//
//   a. `desktop.checkout_intents`, primary-keyed on user_id. Taken BEFORE Stripe is
//      called. Zero rows from the insert means an intent is already open, and this
//      returns that session's URL rather than creating a second one.
//   b. A Stripe idempotency key on the session creation, stored on the intent. Two
//      concurrent requests that both somehow get past (a) still create one session.
//   c. A 30-minute expiry, so an abandoned checkout clears itself instead of
//      blocking a retry for a day.
//   d. A pre-flight state check: a qualifying subscription already live returns the
//      Billing Portal instead, and an `incomplete` one returns its existing payment
//      URL rather than starting a parallel purchase.
//
// **The price is resolved from a lookup key SERVER-side.** `prompt/`'s
// `billing-handlers.js` takes `priceId` straight off the client; §7 says plainly not
// to copy that. The client sends `pro_monthly_jpy` or `pro_yearly_jpy` and nothing
// else is sellable.
//
// Two things the client may now also say, and one it may not:
//
//   - `currency` — `jpy` or `usd`, allow-listed here. Sent rather than left to
//     Stripe's IP localization because the app has already shown the user a price
//     and 「表示価格が実際にご請求される金額です」 is a claim about exactly that gap.
//     Both currencies are `currency_options` on the SAME two prices, so this changes
//     the presentment, not the product.
//   - `locale` — which language Checkout renders in. Was hard-coded `ja`.
//
// **It may not ask for the welcome discount.** Eligibility is read from
// `desktop.welcome_offers` here, on every request, and a client that says it has an
// offer gets nothing for saying so. A discount a client can request is a discount
// anyone can take.

import {
  BILLING_CURRENCIES,
  BillingCurrency,
  CHECKOUT_LOCALES,
  claimsFromAuthHeader,
  corsHeaders,
  desktopRPC,
  desktopRPCRow,
  json,
  jsonError,
  PRICE_LOOKUP_KEYS,
  PriceLookupKey,
  SITE_URL,
  stripe,
  StripeError,
  welcomeCouponId,
} from "../_shared/billing.ts";

/// §3.3c. Stripe's `expires_at` accepts 30 minutes to 24 hours and defaults to 24.
/// A short window is what we want — an abandoned checkout should not hold the intent
/// lock for a day — and the DB row and the Stripe session are given the SAME
/// timestamp so neither outlives the other.
///
/// **35 minutes, not 30, and the five minutes are margin.** The spec says the value
/// may be "anywhere from 30 minutes to 24 hours after Checkout Session creation",
/// measured on Stripe's clock when it handles the request. The timestamp we send is
/// minted earlier, by `now()` inside `desktop_open_checkout_intent` — and between
/// that `now()` and Stripe reading it sit the RPC's return trip, the `/v1/prices`
/// lookup and the session POST. A 30-minute TTL therefore arrives as
/// 29-point-something minutes. `Math.floor` on the way out costs up to another
/// second, and our clock and Stripe's need not agree either.
///
/// Whether Stripe actually rejects that shortfall was never observed: the misplaced
/// `billing_mode` below failed the request first and masked everything after it. So
/// this margin is a guard against a boundary the spec plainly describes, not a fix
/// for a diagnosed failure. It stays well inside the 24-hour ceiling and the intent
/// is still short-lived enough that a retry is never blocked for long.
const INTENT_TTL_SECONDS = 2100;

/// Stripe's documented floor, kept as its own constant because it is THEIR number:
/// the TTL above may be tuned freely, this may not.
const STRIPE_MIN_SESSION_TTL_SECONDS = 1800;

/// Headroom over the floor below which an existing intent is too old to hang a new
/// session off. Covers the same round trips as the margin above.
const CLOCK_SKEW_MARGIN_SECONDS = 120;

const PRO_STATUSES = new Set(["active", "trialing", "past_due"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonError("method_not_allowed", "Use POST.", 405);

  const claims = claimsFromAuthHeader(req.headers.get("Authorization") ?? "");
  if (!claims) return jsonError("unauthorized", "サインインしてください。", 401);
  const userId = claims.sub;

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    // An empty body is fine — the price key is validated below either way.
  }

  const priceKey = body?.price_lookup_key;
  if (!PRICE_LOOKUP_KEYS.includes(priceKey)) {
    return jsonError("invalid_request", "プランを選択してください。", 400);
  }

  // Absent means yen. Every installed build older than this field is a Japanese
  // build, so the default reproduces their behaviour exactly rather than falling
  // into a neutral branch — the same argument `RewriteRequest.writingLanguage`
  // already makes for absent meaning Japanese on the rewrite path.
  const currency: BillingCurrency = BILLING_CURRENCIES.includes(body?.currency)
    ? body.currency
    : "jpy";
  const locale = CHECKOUT_LOCALES.includes(body?.locale) ? body.locale : "ja";
  const interval: "month" | "year" = priceKey === "pro_yearly_jpy" ? "year" : "month";

  try {
    const state = await desktopRPCRow("desktop_billing_state", { p_user_id: userId });

    // (d) Pre-flight. A live subscription means the user wants to MANAGE, not buy.
    if (state?.stripe_subscription_id && PRO_STATUSES.has(state.status ?? "")) {
      return json({ url: await portalURL(state.stripe_customer_id), kind: "portal" });
    }

    // (d) An `incomplete` subscription is a purchase already in flight. Never
    // granted (§3.1), and never given a parallel session: the user finishes the one
    // they started. Stripe holds the payment intent on the latest invoice.
    if (state?.stripe_subscription_id && state.status === "incomplete") {
      const existing = await incompletePaymentURL(state.stripe_subscription_id);
      if (existing) return json({ url: existing, kind: "payment" });
    }

    const customerId = await resolveCustomer(userId, claims.email, state?.stripe_customer_id);

    // **Eligibility for the welcome discount, read rather than accepted.** One row,
    // one predicate, and it is the same one `desktop_get_entitlement` reports to the
    // app — so a card showing the offer price and a session applying it cannot
    // disagree except by the window closing between them, which is the correct
    // outcome and is why the deadline is checked here and not only there.
    const offer = await desktopRPCRow("desktop_welcome_offer_state", { p_user_id: userId });
    const couponId = offer?.eligible === true ? welcomeCouponId(interval) : null;

    const intentArgs = {
      p_user_id: userId,
      p_price_lookup_key: priceKey,
      p_ttl_seconds: INTENT_TTL_SECONDS,
      p_currency: currency,
      p_coupon_id: couponId,
    };

    // (a) The intent row. `primary key (user_id)` is the lock.
    let intent = await desktopRPCRow("desktop_open_checkout_intent", intentArgs);

    // **Three fields, not one.** §3.3b's idempotency key makes Stripe reject a replay
    // whose parameters differ, so anything that changes what we are about to send has
    // to reopen the intent rather than reuse it. The plan was always one of them;
    // currency joins it (the user switched the interface language mid-window) and so
    // does the coupon — an offer that expired inside the 35 minutes turns a
    // discounted intent into a list-price session, and reusing the key there is an
    // `idempotency_error` the user cannot act on.
    const intentDiffers = intent.price_lookup_key !== priceKey
      || (intent.currency ?? "jpy") !== currency
      || (intent.coupon_id ?? null) !== couponId;

    if (!intent.created && intentDiffers) {
      // Handing back the session they abandoned would silently sell them the other
      // plan, the other currency, or the other price. The old session is expired and
      // a fresh intent opened; §3.3c sanctions calling `/expire` on an explicit retry.
      if (intent.stripe_session_id) {
        await stripe(`/v1/checkout/sessions/${intent.stripe_session_id}/expire`, { method: "POST" })
          .catch(() => {});
      }
      await desktopRPC("desktop_clear_checkout_intent", { p_user_id: userId, p_session_id: null });
      intent = await desktopRPCRow("desktop_open_checkout_intent", intentArgs);
    } else if (!intent.created && intent.session_url) {
      // Double-click, two tabs, or a genuine retry on the same plan. One session.
      return json({ url: intent.session_url, kind: "checkout" });
    }

    // An intent that has been open for a while without ever getting a session (a
    // Stripe error on the first attempt, then a retry ten minutes later) has less
    // than Stripe's 30-minute floor left on it. Reusing its timestamp would fail the
    // create with a validation error the user cannot act on, so the stale intent is
    // dropped and a fresh window opened.
    //
    // **Compared against Stripe's floor, not against our own TTL.** `< TTL` was the
    // original test and it is true even of an intent minted microseconds ago — the
    // row is always at least a round trip old by the time it is read back — so it
    // fired unconditionally and reopened the intent on every single request. That
    // wasted a write and, worse, made the reopen look like a working defence when
    // the fresh row it produced was just as unusable as the one it replaced.
    if (secondsUntil(intent.expires_at) < STRIPE_MIN_SESSION_TTL_SECONDS + CLOCK_SKEW_MARGIN_SECONDS) {
      await desktopRPC("desktop_clear_checkout_intent", { p_user_id: userId, p_session_id: null });
      intent = await desktopRPCRow("desktop_open_checkout_intent", intentArgs);
    }

    const price = await resolvePrice(priceKey);
    const session = await createSession({
      userId,
      customerId,
      priceId: price.id,
      currency,
      locale,
      // From the INTENT, not from the eligibility read above. The two agree on every
      // path that reaches here — a mismatch reopened the intent — and taking it from
      // the row is what keeps the session's parameters a pure function of the
      // idempotency key, which is the same reason `expiresAt` is read from the row.
      couponId: intent.coupon_id ?? null,
      idempotencyKey: intent.idempotency_key,
      // Derived from the INTENT, never from `Date.now()`. The idempotency key is
      // per-intent, and Stripe rejects a replay of the same key whose parameters
      // differ — a clock-based expiry would change on every retry and turn (b)'s
      // defence into an `idempotency_error`. Anchoring it to the row makes the
      // parameters a pure function of the key, which is what makes the retry safe.
      expiresAt: Math.floor(new Date(intent.expires_at).getTime() / 1000),
    });

    await desktopRPC("desktop_attach_checkout_session", {
      p_user_id: userId,
      p_session_id: session.id,
      p_session_url: session.url,
    });

    console.log(JSON.stringify({
      event: "desktop_checkout",
      userId,
      priceKey,
      currency,
      // Whether the discount was actually applied, from the row that decided it. The
      // client reports what it expected (`offer_expected`); the two disagreeing is
      // the signal worth having, and neither is inferable from the other.
      offerApplied: (intent.coupon_id ?? null) !== null,
      sessionId: session.id,
      reusedIntent: !intent.created,
      status: "ok",
    }));

    return json({ url: session.url, kind: "checkout" });
  } catch (error) {
    const stripeError = error instanceof StripeError ? error : null;
    console.error(JSON.stringify({
      event: "desktop_checkout",
      userId,
      priceKey,
      status: stripeError ? "stripe_error" : "error",
      code: stripeError?.code,
      message: error instanceof Error ? error.message : "unknown",
    }));
    return jsonError("checkout_failed", "決済ページを開けませんでした。", 502);
  }
});

// ---------------------------------------------------------------------------

/// One Stripe customer per user, forever.
///
/// The race is real and the resolution is asymmetric on purpose: two concurrent
/// first-time checkouts can both create a customer at Stripe, but
/// `desktop.subscriptions.stripe_customer_id` is NOT NULL UNIQUE and only one write
/// wins. `desktop_link_stripe_customer` returns the id that IS in force, and the
/// loser abandons its own. An empty customer with no invoices costs nothing and is
/// left in place — §0's rule is that a customer carrying a settled payment is a 帳簿
/// record, and the cheap way to never breach it is to not delete customers at all.
async function resolveCustomer(
  userId: string,
  email: string | undefined,
  known: string | null | undefined,
): Promise<string> {
  if (known) return known;

  const created = await stripe("/v1/customers", {
    method: "POST",
    body: {
      email,
      metadata: { supabase_user_id: userId, surface: "macos" },
    },
    // Bounded by the user, not by time: a retry within Stripe's 24-hour key window
    // returns the same customer instead of a second one.
    idempotencyKey: `desktop_customer:${userId}`,
  });

  const inForce = await desktopRPC("desktop_link_stripe_customer", {
    p_user_id: userId,
    p_stripe_customer_id: created.id,
  });

  if (inForce && inForce !== created.id) {
    console.warn(JSON.stringify({
      event: "desktop_checkout_customer_race",
      userId,
      abandoned: created.id,
      inForce,
    }));
  }
  return inForce ?? created.id;
}

/// §2: `lookup_key` finds the price to SELL, and it is never the entitlement check.
/// `transfer_lookup_key: true` strips the key off the old price on a price change,
/// so a grandfathered subscriber's price has no lookup key at all — which is exactly
/// why entitlement validates the product id instead (§3.2, enforced in SQL).
///
/// `active: true` matters: an archived price cannot start a new subscription, and
/// that is the failure behind §9 row 4's resubscribe path.
async function resolvePrice(lookupKey: PriceLookupKey): Promise<any> {
  const result = await stripe("/v1/prices", {
    query: { lookup_keys: [lookupKey], active: true, limit: 2 },
  });
  const price = result?.data?.[0];
  if (!price) throw new Error(`no active price for lookup_key ${lookupKey}`);
  return price;
}

async function createSession(params: {
  userId: string;
  customerId: string;
  priceId: string;
  currency: string;
  locale: string;
  couponId: string | null;
  idempotencyKey: string;
  expiresAt: number;
}): Promise<{ id: string; url: string }> {
  // §10 — **Core7 is a 免税事業者 and is not an 適格請求書発行事業者.** So tax is
  // deliberately OFF, and that is the correct end state rather than a step not yet
  // taken: a 免税事業者 may not issue a 適格請求書, and an invoice showing 適用税率 or
  // 消費税額等 would misrepresent what we are.
  //
  // Sent EXPLICITLY as false rather than omitted. Stripe's default happens to be
  // false today, but this is a legal position, not a preference, and a default is
  // the wrong place to keep one — a future SDK or API-version change to the default
  // would flip it silently and the symptom would be an invoice that looks fine.
  //
  // The env var stays as the single switch for the day the 1,000万円 threshold makes
  // us a 課税事業者 (§10). Flipping it alone is not enough then: the JP registration
  // under Tax → Locations and `account_tax_ids` have to exist first, or Stripe
  // computes ¥0 and the invoice is silently non-compliant.
  const automaticTax = Deno.env.get("DESKTOP_STRIPE_AUTOMATIC_TAX") === "true";

  const session = await stripe("/v1/checkout/sessions", {
    method: "POST",
    idempotencyKey: params.idempotencyKey,
    body: {
      mode: "subscription",
      customer: params.customerId,
      line_items: [{ price: params.priceId, quantity: 1 }],
      // **The presentment currency, stated rather than detected.** Both currencies
      // are `currency_options` on this same price; passing it explicitly overrides
      // Checkout's IP-based localization, which would otherwise quote an English user
      // in Japan in yen after the app had shown them dollars.
      currency: params.currency,
      // **`discounts` and `allow_promotion_codes` are mutually exclusive** — a
      // Checkout Session supports at most one coupon or promotion code, and sending
      // both is a hard 400. So this is an either/or rather than two fields:
      //
      //   - Offer live → the coupon is applied by us, server-side, from a row the
      //     client cannot influence. The promotion-code box is gone, which is correct:
      //     a session already carrying the best price we offer has nothing to stack.
      //   - Otherwise → the box comes back, which is what makes a cohort code like
      //     「最初の100名は初年度 ¥9,800」 (§2: a promotion code with `duration: once`,
      //     never a third price) redeemable at all.
      ...(params.couponId
        ? { discounts: [{ coupon: params.couponId }] }
        : { allow_promotion_codes: true }),
      locale: params.locale,
      expires_at: params.expiresAt,
      // Two independent ways for the webhook to find the user even if our own
      // customer row is somehow missing.
      client_reference_id: params.userId,
      subscription_data: {
        metadata: { supabase_user_id: params.userId, surface: "macos" },
        // §2. Flexible computes credit prorations from the amount ORIGINALLY
        // debited, and it is what E-UP's `billing_cycle_anchor: 'now'` +
        // `proration_behavior: 'always_invoice'` pair assumes. THE MIGRATION IS
        // ONE-WAY — a subscription created without this cannot be moved onto it.
        //
        // **Nested under `subscription_data`, NOT top-level.** The Subscriptions
        // API takes `billing_mode` at the top level and Checkout does not; sending
        // it there is a hard `parameter_unknown` on every request, which is how
        // this shipped broken. Verified against the OpenAPI spec rather than the
        // prose docs — the prose links "a Checkout Session" straight at
        // `create_checkout_session-billing_mode` and never says which level.
        billing_mode: { type: "flexible" },
      },
      automatic_tax: { enabled: automaticTax },
      // Only needed to let Stripe Tax infer a location. With tax off there is
      // nothing to infer, and asking Checkout to overwrite the customer's address
      // would be collecting data we have no use for.
      customer_update: automaticTax ? { address: "auto" } : undefined,
      success_url: `${SITE_URL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE_URL}/billing/cancelled`,
    },
  });
  return { id: session.id, url: session.url };
}

/// The hosted invoice page for a subscription stuck at `incomplete`. Returning this
/// rather than a new session is §9 row 23: never granted on `incomplete`, and never
/// given a parallel purchase to abandon halfway.
async function incompletePaymentURL(subscriptionId: string): Promise<string | null> {
  try {
    const sub = await stripe(`/v1/subscriptions/${subscriptionId}`, {
      query: { expand: ["latest_invoice"] },
    });
    const invoice = sub?.latest_invoice;
    return typeof invoice?.hosted_invoice_url === "string" ? invoice.hosted_invoice_url : null;
  } catch {
    return null;
  }
}

function secondsUntil(timestamp: string): number {
  const at = new Date(timestamp).getTime();
  return Number.isFinite(at) ? (at - Date.now()) / 1000 : 0;
}

async function portalURL(customerId: string): Promise<string> {
  const session = await stripe("/v1/billing_portal/sessions", {
    method: "POST",
    body: { customer: customerId, return_url: `${SITE_URL}/billing/return` },
  });
  return session.url;
}
