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
  const token = Deno.env.get("POSTHOG_PROJECT_TOKEN");
  const host = Deno.env.get("POSTHOG_HOST") ?? "https://us.i.posthog.com";

  if (!token) {
    // Loud rather than silent, and non-fatal: the same posture as §1's layer 2. A
    // deploy that forgot the secret should be visible in the function logs rather
    // than showing up a week later as a tile that never moved.
    console.warn(JSON.stringify({
      event: "desktop_posthog_capture",
      status: "no_project_token",
      posthogEvent: event,
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
