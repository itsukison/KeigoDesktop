// Server-side PostHog capture, for the events only the server can know.
//
// `docs/analytics.md` §3, "Closed on 2026-08-22": "No `desktop_checkout_completed`. The revenue funnel
// ends at intent. The Stripe webhook knows the answer server-side; nothing forwards
// it." This is the forwarder. As of 2026-08-22 `desktop_checkout_started` had never
// fired even once, so the whole of band 5's revenue half was two empty tiles — and the
// client could not have closed the gap even in principle: Checkout hands off to the
// DEFAULT BROWSER (see `AppDelegate`'s `keigobutton://billing` leg), so the app is not
// running when the purchase completes and a `success_url` redirect is not proof of
// payment (§3.3 — that is how an unpaid session gets granted Pro).
//
// Three rules this module exists to keep:
//
//   1. **Analytics never break billing.** Every function here swallows its own errors.
//      A PostHog outage, a missing token, a 500 — none of them may turn into a 5xx from
//      the webhook, because that makes Stripe retry an event that was fully processed.
//   2. **`surface: macos` is stamped by hand.** There is no SDK here, so there is no
//      super property. §1's layer 2 says every event in project 549465 carries the
//      surface; an event that arrives without one is a leak, and this module must not
//      be the thing that makes that signal unreliable.
//   3. **`distinct_id` is the Supabase user id**, the same id the app identifies with,
//      so a server event lands on the same person as the client events either side of
//      it. That is the whole reason the funnel joins up.

/// PostHog's ingestion endpoint. `/i/v0/e/` is the current single-event route; the
/// project token authenticates it, which is why it is the *project* token here and not
/// the personal API key — this writes events, it does not read anything.
const CAPTURE_PATH = "/i/v0/e/";

/// Bounded so a slow ingest endpoint cannot hold the webhook open. Stripe's own
/// delivery timeout is what is actually at stake: the handler has already written the
/// entitlement by the time this runs, and losing one analytics event is strictly
/// cheaper than losing the 200 that marks the Stripe event processed.
const TIMEOUT_MS = 3_000;

/// The one project this module is allowed to write to: 549465,
/// `KeigoButton Desktop (macOS)`. Pinned in code, not merely configured, and checked
/// against whatever the environment supplies before a single event is sent.
///
/// **This is layer 1 of `docs/analytics.md` §1, enforced rather than assumed.** The
/// client gets layer 1 for free — the app is built with its own token baked in by its
/// own release workflow. The server does not: `keyboard-rewrite` (project 465060),
/// `web-rewrite` and every desktop function share ONE Supabase project
/// (`eercsucvxnszqletxued`), and therefore ONE secrets namespace. A secret named
/// `POSTHOG_PROJECT_TOKEN` cannot mean two different projects at once, so the first
/// surface to set it silently redirects the other.
///
/// That is not hypothetical. Deploying `desktop-stripe-webhook` on 2026-08-23 11:55 JST
/// set the shared `POSTHOG_PROJECT_TOKEN` to the desktop token; `keyboard-rewrite` reads
/// the same name in preference to its own hard-coded default, so from 13:50 JST the iOS
/// keyboard's `ai_rewrite` events (198 of them, 49 people) landed in 549465 and stopped
/// arriving in 465060 entirely. A redirect, not a duplicate: the keyboard's own analytics
/// went dark and nothing anywhere raised a warning.
///
/// Two things prevent the recurrence, and both are needed:
///
///   1. **A surface-specific secret name** (`DESKTOP_POSTHOG_PROJECT_TOKEN`), so the two
///      surfaces cannot collide in the shared namespace in the first place.
///   2. **This pin**, so that if they ever do collide again — a typo, a copied deploy
///      script, a third surface — the write is *refused and logged* rather than landing
///      in the wrong project. A misconfiguration that loses one event is recoverable;
///      one that silently pollutes another surface's person store is not (§1: "the
///      damage is to the person store, not to the event stream").
///
/// Safe to hard-code: a `phc_` project token is a write-only public credential that
/// ships inside every client binary. It is not a secret, which is exactly why pinning it
/// costs nothing and buys the guarantee.
const EXPECTED_PROJECT_TOKEN = "phc_sJZEvNvRET7BEwCwXNnzoRofkbowJ8Ec3TuQTz9hHrG6";

/// Fire-and-report. Resolves either way; never rejects.
///
/// Awaited rather than detached at the call site on purpose — an Edge Function's
/// isolate can be torn down the moment the response is returned, so a floating promise
/// is a dropped event rather than a background one.
export async function capture(
  distinctId: string,
  event: string,
  properties: Record<string, unknown>,
): Promise<void> {
  // Surface-specific name. NOT `POSTHOG_PROJECT_TOKEN` — that name is shared with
  // `keyboard-rewrite` in the same Supabase project and setting it redirects the
  // keyboard's analytics into this project. See `EXPECTED_PROJECT_TOKEN`.
  const token = Deno.env.get("DESKTOP_POSTHOG_PROJECT_TOKEN") ?? EXPECTED_PROJECT_TOKEN;
  const host = Deno.env.get("POSTHOG_HOST") ?? "https://us.i.posthog.com";

  // Refuse to write to any project but the desktop's. A mismatch means the secret has
  // been pointed somewhere else, and sending anyway would put desktop events into
  // another surface's person store — the one failure §1 says is unrecoverable.
  if (token !== EXPECTED_PROJECT_TOKEN) {
    console.warn(JSON.stringify({
      event: "desktop_posthog_capture",
      status: "wrong_project_token",
      posthogEvent: event,
      // Prefix only, so the log names the mistake without reprinting a credential.
      configuredPrefix: token.slice(0, 12),
      expectedPrefix: EXPECTED_PROJECT_TOKEN.slice(0, 12),
    }));
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${host.replace(/\/+$/, "")}${CAPTURE_PATH}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        api_key: token,
        event,
        distinct_id: distinctId,
        properties: {
          // Rule 2. Hard-coded because this module only ever serves the desktop's
          // functions — if a second surface ever calls it, this becomes a parameter
          // rather than a default.
          surface: "macos",
          // Names the writer, so a server event and a client event of the same name
          // are separable. Nothing sends both today and nothing should, but the
          // property costs nothing and the ambiguity would cost a re-instrumentation.
          captured_by: "server",
          ...properties,
        },
      }),
    });
    if (!response.ok) {
      console.warn(JSON.stringify({
        event: "desktop_posthog_capture",
        status: "rejected",
        httpStatus: response.status,
        posthogEvent: event,
      }));
    }
  } catch (error) {
    console.warn(JSON.stringify({
      event: "desktop_posthog_capture",
      status: "error",
      posthogEvent: event,
      message: error instanceof Error ? error.message : "unknown",
    }));
  } finally {
    clearTimeout(timer);
  }
}
