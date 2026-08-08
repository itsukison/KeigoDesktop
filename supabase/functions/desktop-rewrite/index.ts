// desktop-rewrite
//
// The macOS surface's rewrite endpoint. Deliberately a SEPARATE function from
// `keyboard-rewrite`, not a branch inside it (AGENTS.md §6):
//
//   - `keyboard-rewrite` belongs to the shipped iOS keyboard. It is on the typing
//     path of thousands of live users and must not gain a second caller with
//     different fields, different limits, and a different event table.
//   - Events land in `desktop.rewrite_events`, never `ai_rewrite_events`. Mixing
//     surfaces would make every existing query on that table silently wrong.
//
// Accepts a SUPERSET of the shared `RewriteRequest`: `surface`, `hostAppBundleId`,
// `captureMode`, `browserURL` are additive, so the Swift model stays compatible
// with the iOS one.
//
// `verify_jwt = true` in config.toml. The gateway validates the JWT before this
// runs, so the `sub` claim is trusted without a round trip to the auth service —
// same posture as `keyboard-rewrite`. Do not set that to false.

import { redactPII } from "./redact.ts";

type ProviderName = "openai" | "azure" | "cerebras" | "groq";
const ALL_PROVIDERS: ProviderName[] = ["openai", "azure", "cerebras", "groq"];

type CaptureMode = "wholeInput" | "selection" | "fullDocument";
type RefinementIntent = "morePolite" | "moreDetailed" | "moreConcise";

type DesktopRewriteRequest = {
  prompt: string;
  text: string;
  replyTo?: string | null;
  commandKey?: string | null;
  title?: string | null;
  promptOrigin?: string | null;
  locale?: string;
  appVersion?: string;
  candidateCount: number;
  refinement?: RefinementIntent | null;
  selection?: boolean;
  selectionContextBefore?: string | null;
  selectionContextAfter?: string | null;
  stream?: boolean;
  // macOS superset
  surface?: string;
  hostAppBundleId?: string | null;
  captureMode: CaptureMode;
  browserURL?: string | null;
  /// 'ax' | 'clipboard'. Only the client knows which path it actually used, and
  /// §7 makes this the earliest signal that an app's AX tree changed — so it has
  /// to come over the wire or the column is permanently null.
  ioPath?: "ax" | "clipboard" | null;
};

type RewriteCandidate = { replacement: string; changed: boolean };
type RewriteResult = { candidates: RewriteCandidate[]; language: string };

const MIN_CANDIDATES = 1;
const MAX_CANDIDATES = 5;
const DEFAULT_CANDIDATES = 3;
const MAX_PROMPT_CHARS = 1000;

// Desktop input is a whole mail draft or document field, not a phone message, so
// the ceiling is higher than the keyboard's 2000. Still bounded — this is what
// caps prompt cost per call.
const DEFAULT_MAX_TEXT_CHARS = 6000;

const DEFAULT_CONSENT_VERSION = "2026-07-02";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class ProviderError extends Error {
  constructor(
    public readonly provider: ProviderName,
    public readonly code: "content_blocked" | "provider_rate_limited" | "provider_error",
    public readonly userMessage: string,
    message: string,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

function envInt(key: string, fallback: number): number {
  const raw = Deno.env.get(key);
  const parsed = raw ? Number.parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) ? parsed : fallback;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function jsonError(code: string, message: string, status: number): Response {
  return json({ error: { code, message } }, status);
}

/// The gateway already validated the signature; this only reads the claim.
function userIdFromAuthHeader(header: string): string | null {
  const token = header.replace(/^Bearer\s+/i, "");
  const segments = token.split(".");
  if (segments.length < 2) return null;
  try {
    const padded = segments[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(padded + "=".repeat((4 - padded.length % 4) % 4)));
    return typeof payload?.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonError("method_not_allowed", "Use POST.", 405);

  const userId = userIdFromAuthHeader(req.headers.get("Authorization") ?? "");
  if (!userId) return jsonError("unauthorized", "Invalid session.", 401);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonError("invalid_json", "Request body must be JSON.", 400);
  }

  // Feedback and action posts share this endpoint, matching how the iOS side
  // folds them into `keyboard-rewrite`.
  if (typeof body?.eventId === "string" && typeof body?.action === "string") {
    return await handleAction(userId, body);
  }
  if (typeof body?.eventId === "string" && typeof body?.selectedIndex === "number") {
    return await handleSelection(userId, body);
  }

  const parsed = parseRequest(body);
  if ("error" in parsed) return parsed.error;
  const request = parsed.value;

  const maxChars = envInt("DESKTOP_MAX_REWRITE_CHARS", DEFAULT_MAX_TEXT_CHARS);
  for (const field of [request.text, request.replyTo, request.selectionContextBefore, request.selectionContextAfter]) {
    if (field && [...field].length > maxChars) {
      return jsonError("text_too_long", "文章が長すぎます。", 413);
    }
  }
  if ([...request.prompt].length > MAX_PROMPT_CHARS) {
    return jsonError("prompt_too_long", "プロンプトが長すぎます。", 413);
  }

  const providers = configuredProviders();
  if (providers.length === 0) {
    return jsonError("configuration_missing", "AIの設定が不足しています。", 503);
  }

  // Same posture as keyboard-rewrite: the usage guard is a full Postgres round
  // trip, so it runs alongside the provider call rather than in front of it.
  const guardStartedAt = Date.now();
  const usagePromise = reserveUsage(userId, request.candidateCount)
    .then((value) => ({ ...value, guardMs: Date.now() - guardStartedAt }));

  const rewritePromise = rewriteWithProviders(providers, request);
  // Without a handler attached here, a guard denial would surface the provider
  // rejection as unhandled and take down the isolate.
  rewritePromise.catch(() => {});

  const usage = await usagePromise;
  if (!usage.allowed) return jsonError("rate_limited", usage.message, 429);

  try {
    const rewrite = await rewritePromise;
    const latencyMs = Date.now() - startedAt;
    const eventId = crypto.randomUUID();

    console.log(JSON.stringify({
      event: "desktop_rewrite",
      provider: rewrite.provider,
      model: rewrite.model,
      userId,
      surface: "macos",
      hostAppBundleId: request.hostAppBundleId,
      captureMode: request.captureMode,
      commandKey: request.commandKey,
      promptOrigin: request.promptOrigin,
      candidateCount: rewrite.result.candidates.length,
      inputLength: [...request.text].length,
      latencyMs,
      guardMs: usage.guardMs,
      status: "ok",
    }));

    (globalThis as any).EdgeRuntime?.waitUntil(Promise.all([
      logRewriteEvent(eventId, { userId, request, result: rewrite.result, provider: rewrite.provider, model: rewrite.model, latencyMs }),
      recordActivation(userId, request.appVersion ?? "unknown"),
    ]));

    return json({ ...rewrite.result, eventId });
  } catch (error) {
    const providerError = error instanceof ProviderError ? error : null;
    console.error(JSON.stringify({
      event: "desktop_rewrite",
      userId,
      surface: "macos",
      hostAppBundleId: request.hostAppBundleId,
      status: providerError?.code ?? "provider_error",
      message: error instanceof Error ? error.message : "unknown error",
    }));
    if (providerError) {
      const status = providerError.code === "content_blocked"
        ? 422
        : providerError.code === "provider_rate_limited"
        ? 429
        : 502;
      return jsonError(providerError.code, providerError.userMessage, status);
    }
    return jsonError("provider_error", "AIの処理に失敗しました。少し待ってからもう一度お試しください。", 502);
  }
});

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

function parseRequest(body: unknown): { value: DesktopRewriteRequest } | { error: Response } {
  if (!body || typeof body !== "object") {
    return { error: jsonError("invalid_request", "Request body must be an object.", 400) };
  }
  const data = body as Record<string, unknown>;

  if (typeof data.prompt !== "string" || data.prompt.trim().length === 0) {
    return { error: jsonError("invalid_request", "`prompt` is required.", 400) };
  }
  if (typeof data.text !== "string") {
    return { error: jsonError("invalid_request", "`text` is required.", 400) };
  }

  const captureMode = data.captureMode;
  if (captureMode !== "wholeInput" && captureMode !== "selection" && captureMode !== "fullDocument") {
    return { error: jsonError("invalid_request", "`captureMode` is invalid.", 400) };
  }

  const rawCount = typeof data.candidateCount === "number" ? data.candidateCount : DEFAULT_CANDIDATES;
  const candidateCount = Math.min(MAX_CANDIDATES, Math.max(MIN_CANDIDATES, Math.floor(rawCount)));

  const optionalString = (value: unknown): string | null =>
    typeof value === "string" && value.length > 0 ? value : null;

  return {
    value: {
      prompt: data.prompt,
      text: data.text,
      replyTo: optionalString(data.replyTo),
      commandKey: optionalString(data.commandKey),
      title: optionalString(data.title),
      promptOrigin: optionalString(data.promptOrigin),
      locale: typeof data.locale === "string" ? data.locale : "ja-JP",
      appVersion: typeof data.appVersion === "string" ? data.appVersion : "unknown",
      candidateCount,
      refinement: (["morePolite", "moreDetailed", "moreConcise"] as const)
        .includes(data.refinement as RefinementIntent)
        ? data.refinement as RefinementIntent
        : null,
      selection: data.selection === true || captureMode === "selection",
      selectionContextBefore: optionalString(data.selectionContextBefore),
      selectionContextAfter: optionalString(data.selectionContextAfter),
      stream: data.stream === true,
      surface: typeof data.surface === "string" ? data.surface : "macos",
      hostAppBundleId: optionalString(data.hostAppBundleId),
      captureMode,
      browserURL: optionalString(data.browserURL),
      ioPath: data.ioPath === "ax" || data.ioPath === "clipboard" ? data.ioPath : null,
    },
  };
}

// ---------------------------------------------------------------------------
// Usage guard
// ---------------------------------------------------------------------------

/// Fails CLOSED, unlike `web-rewrite`'s per-IP counter. That endpoint is an
/// unauthenticated free tool where a database hiccup should degrade rather than
/// break; this one is authenticated and metered, so an unmeasurable request is
/// one we decline.
async function reserveUsage(
  userId: string,
  units: number,
): Promise<{ allowed: boolean; message: string }> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return { allowed: false, message: "利用状況を確認できませんでした。少し待ってからもう一度お試しください。" };
  }

  const now = new Date().toISOString();
  const checks: Array<[string, number, "units" | "requests", string]> = [
    [`day:${now.slice(0, 10)}`, envInt("DESKTOP_DAILY_UNITS", 900), "units", "本日のAI利用上限に達しました。明日もう一度お試しください。"],
    [`hour:${now.slice(0, 13)}`, envInt("DESKTOP_HOURLY_REQUESTS", 120), "requests", "短時間のAI利用が多すぎます。少し待ってからもう一度お試しください。"],
    [`minute:${now.slice(0, 16)}`, envInt("DESKTOP_MINUTE_REQUESTS", 12), "requests", "短時間のAI利用が多すぎます。少し待ってからもう一度お試しください。"],
  ];

  try {
    for (const [bucketKey, limit, field, message] of checks) {
      // The tables live in the `desktop` schema, but every entry point is a
      // SECURITY DEFINER function in `public` — see the migration header. That is
      // what keeps this working without adding `desktop` to the shared project's
      // exposed-schema list.
      const res = await fetch(`${url}/rest/v1/rpc/desktop_bump_usage`, {
        method: "POST",
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_user_id: userId,
          p_bucket_key: bucketKey,
          p_units: units,
        }),
      });
      if (!res.ok) {
        console.error(JSON.stringify({
          event: "desktop_rewrite_usage_guard",
          status: "error",
          httpStatus: res.status,
          message: (await res.text()).slice(0, 300),
        }));
        return { allowed: false, message: "利用状況を確認できませんでした。少し待ってからもう一度お試しください。" };
      }
      const rows = await res.json();
      const row = Array.isArray(rows) ? rows[0] : rows;
      if (Number(row?.[field]) > limit) return { allowed: false, message };
    }
    return { allowed: true, message: "" };
  } catch (error) {
    console.error(JSON.stringify({
      event: "desktop_rewrite_usage_guard",
      status: "exception",
      message: error instanceof Error ? error.message : "unknown",
    }));
    return { allowed: false, message: "利用状況を確認できませんでした。少し待ってからもう一度お試しください。" };
  }
}

// ---------------------------------------------------------------------------
// Persistence — desktop schema only
// ---------------------------------------------------------------------------

/// Calls one of the `public.desktop_*` SECURITY DEFINER entry points. No desktop
/// table is reachable over the API directly — see the migration header.
async function desktopRPC(fn: string, args: unknown): Promise<Response | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;

  try {
    return await fetch(`${url}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
    });
  } catch {
    return null;
  }
}

async function logRewriteEvent(
  eventId: string,
  input: {
    userId: string;
    request: DesktopRewriteRequest;
    result: RewriteResult;
    provider: ProviderName;
    model: string;
    latencyMs: number;
  },
): Promise<void> {
  if ((Deno.env.get("DESKTOP_EVENT_LOGGING_ENABLED") ?? "true") === "false") return;

  const { userId, request, result, provider, model, latencyMs } = input;

  // Fail closed on text retention: it is opt-in, and the consent record is the
  // shared `user_ai_consent` table both surfaces honour.
  const consent = await fetchConsent(userId);
  const storeText = consent.optIn;

  await desktopRPC("desktop_log_rewrite_event", {
    p_event: {
      id: eventId,
      user_id: userId,
      command_key: request.commandKey,
      prompt_origin: request.promptOrigin,
      capture_mode: request.captureMode,
      host_app_bundle_id: request.hostAppBundleId,
      io_path: request.ioPath,
      locale: request.locale,
      app_version: request.appVersion,
      candidate_count: result.candidates.length,
      input_length: [...request.text].length,
      output_length: result.candidates.reduce((sum, c) => sum + [...c.replacement].length, 0),
      latency_ms: latencyMs,
      provider,
      model,
      status: "ok",
      input_text: storeText ? redactPII(request.text) : null,
      output_text: storeText ? redactPII(result.candidates[0]?.replacement ?? "") : null,
      consent_version: storeText ? (consent.version ?? DEFAULT_CONSENT_VERSION) : null,
    },
  });
}

/// Reads the SHARED `user_ai_consent` table. Read-only — the desktop app never
/// writes it, so a user's consent state is owned by whichever surface asked.
async function fetchConsent(userId: string): Promise<{ optIn: boolean; version: string | null }> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return { optIn: false, version: null };

  try {
    const res = await fetch(
      `${url}/rest/v1/user_ai_consent?select=opt_in,consent_version&user_id=eq.${userId}&limit=1`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } },
    );
    if (!res.ok) return { optIn: false, version: null };
    const rows = await res.json();
    const row = Array.isArray(rows) ? rows[0] : null;
    return {
      optIn: row?.opt_in === true,
      version: typeof row?.consent_version === "string" ? row.consent_version : null,
    };
  } catch {
    return { optIn: false, version: null };
  }
}

/// §6: desktop MAU is counted from `desktop.activations`, never by counting
/// `profiles` rows — that table holds both platforms' users.
async function recordActivation(userId: string, appVersion: string): Promise<void> {
  await desktopRPC("desktop_record_activation", {
    p_user_id: userId,
    p_app_version: appVersion,
  });
}

// ---------------------------------------------------------------------------
// Feedback — implemented from day one (§6)
// ---------------------------------------------------------------------------

/// The `p_user_id` predicate is enforced inside the function, not here: the event
/// id comes from the client, so without it one user could annotate another's event.
async function patchEvent(
  userId: string,
  eventId: string,
  patch: {
    p_action?: string | null;
    p_selected_index?: number | null;
    p_latency_ms?: number | null;
    p_accepted?: boolean | null;
  },
): Promise<Response> {
  const res = await desktopRPC("desktop_patch_rewrite_event", {
    p_event_id: eventId,
    p_user_id: userId,
    ...patch,
  });
  if (!res) return json({ ok: false }, 503);
  return json({ ok: res.ok }, res.ok ? 200 : 502);
}

async function handleSelection(userId: string, body: any): Promise<Response> {
  return await patchEvent(userId, body.eventId, {
    p_selected_index: body.selectedIndex,
    p_accepted: true,
  });
}

async function handleAction(userId: string, body: any): Promise<Response> {
  const allowed = new Set(["copy", "regenerate", "thumbs_up", "thumbs_down", "dismiss", "replace_failed"]);
  if (!allowed.has(body.action)) {
    return jsonError("invalid_request", "Unknown action.", 400);
  }
  return await patchEvent(userId, body.eventId, {
    p_action: body.action,
    p_selected_index: typeof body.selectedIndex === "number" ? body.selectedIndex : null,
    p_latency_ms: typeof body.latencyMs === "number" ? body.latencyMs : null,
  });
}

// ---------------------------------------------------------------------------
// Providers — same ladder and env var names as keyboard-rewrite, so both
// functions are configured by one set of secrets.
// ---------------------------------------------------------------------------

function providerHasKey(provider: ProviderName): boolean {
  switch (provider) {
    case "openai":
      return !!Deno.env.get("OPENAI_API_KEY");
    case "azure":
      return !!Deno.env.get("AZURE_OPENAI_API_KEY") && !!Deno.env.get("AZURE_OPENAI_ENDPOINT");
    case "cerebras":
      return !!Deno.env.get("CEREBRAS_API_KEY");
    case "groq":
      return !!Deno.env.get("GROQ_API_KEY");
  }
}

function configuredProviders(): ProviderName[] {
  const requested = Deno.env.get("REWRITE_PROVIDER");
  const primary: ProviderName = ALL_PROVIDERS.includes(requested as ProviderName)
    ? requested as ProviderName
    : "openai";
  const fallbackEnabled = (Deno.env.get("REWRITE_PROVIDER_FALLBACK") ?? "true") !== "false";
  const ordered: ProviderName[] = [primary, ...ALL_PROVIDERS.filter((p) => p !== primary)];
  return ordered.filter((provider, index) => {
    if (index > 0 && !fallbackEnabled) return false;
    return providerHasKey(provider);
  });
}

type ProviderConfig = {
  apiKey: string | undefined;
  model: string;
  endpoint: string;
  authHeaders: Record<string, string>;
  timeoutMs: number;
  baseTokens: number;
  reasoningEffort: string | undefined;
  serviceTier?: string;
};

function resolveProviderConfig(provider: ProviderName): ProviderConfig {
  if (provider === "openai") {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    return {
      apiKey,
      model: Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-terra",
      endpoint: Deno.env.get("OPENAI_CHAT_COMPLETIONS_URL") ?? "https://api.openai.com/v1/chat/completions",
      authHeaders: { Authorization: `Bearer ${apiKey ?? ""}` },
      timeoutMs: envInt("OPENAI_TIMEOUT_MS", 13000),
      baseTokens: envInt("OPENAI_MAX_OUTPUT_TOKENS", 900),
      reasoningEffort: Deno.env.get("OPENAI_REASONING_EFFORT") ?? "low",
      serviceTier: Deno.env.get("OPENAI_SERVICE_TIER") || undefined,
    };
  }
  if (provider === "azure") {
    const base = (Deno.env.get("AZURE_OPENAI_ENDPOINT") ?? "").replace(/\/+$/, "");
    const deployment = Deno.env.get("AZURE_OPENAI_DEPLOYMENT") ?? "gpt-4.1";
    const apiVersion = Deno.env.get("AZURE_OPENAI_API_VERSION") ?? "2025-04-01-preview";
    const apiKey = Deno.env.get("AZURE_OPENAI_API_KEY");
    return {
      apiKey,
      model: deployment,
      endpoint: `${base}/openai/deployments/${deployment}/chat/completions?api-version=${apiVersion}`,
      authHeaders: { "api-key": apiKey ?? "" },
      timeoutMs: envInt("AZURE_TIMEOUT_MS", 14000),
      baseTokens: envInt("AZURE_MAX_OUTPUT_TOKENS", 900),
      reasoningEffort: Deno.env.get("AZURE_REASONING_EFFORT") || undefined,
    };
  }
  if (provider === "cerebras") {
    const apiKey = Deno.env.get("CEREBRAS_API_KEY");
    return {
      apiKey,
      model: Deno.env.get("CEREBRAS_MODEL") ?? "gpt-oss-120b",
      endpoint: Deno.env.get("CEREBRAS_CHAT_COMPLETIONS_URL") ?? "https://api.cerebras.ai/v1/chat/completions",
      authHeaders: { Authorization: `Bearer ${apiKey ?? ""}` },
      timeoutMs: envInt("CEREBRAS_TIMEOUT_MS", 10000),
      baseTokens: envInt("CEREBRAS_MAX_OUTPUT_TOKENS", 900),
      reasoningEffort: Deno.env.get("CEREBRAS_REASONING_EFFORT") || undefined,
    };
  }
  const apiKey = Deno.env.get("GROQ_API_KEY");
  return {
    apiKey,
    model: Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-120b",
    endpoint: Deno.env.get("GROQ_CHAT_COMPLETIONS_URL") ?? "https://api.groq.com/openai/v1/chat/completions",
    authHeaders: { Authorization: `Bearer ${apiKey ?? ""}` },
    timeoutMs: envInt("GROQ_TIMEOUT_MS", 10000),
    baseTokens: envInt("GROQ_MAX_OUTPUT_TOKENS", 900),
    reasoningEffort: Deno.env.get("GROQ_REASONING_EFFORT") || undefined,
  };
}

async function rewriteWithProviders(
  providers: ProviderName[],
  request: DesktopRewriteRequest,
): Promise<{ provider: ProviderName; model: string; result: RewriteResult }> {
  let lastError: unknown;
  const deadlineAt = Date.now() + envInt("DESKTOP_TOTAL_TIMEOUT_MS", 22000);

  for (const provider of providers) {
    try {
      const remainingMs = deadlineAt - Date.now();
      if (remainingMs <= 0) {
        throw new ProviderError(provider, "provider_error", "AIの処理に失敗しました。", "deadline exhausted");
      }
      const output = await rewriteWithProvider(provider, request, remainingMs);
      return { provider, ...output };
    } catch (error) {
      lastError = error;
      const providerError = error instanceof ProviderError ? error : null;
      console.error(JSON.stringify({
        event: "desktop_rewrite_provider_attempt",
        provider,
        status: providerError?.code ?? "provider_error",
        message: error instanceof Error ? error.message : "unknown error",
      }));
      // A content block is a verdict on the input, not a provider fault — trying
      // the next provider would just get the same answer more slowly.
      if (providerError?.code === "content_blocked") throw error;
    }
  }
  throw lastError;
}

async function rewriteWithProvider(
  provider: ProviderName,
  request: DesktopRewriteRequest,
  remainingMs: number,
): Promise<{ model: string; result: RewriteResult }> {
  const config = resolveProviderConfig(provider);
  if (!config.apiKey) {
    throw new ProviderError(provider, "provider_error", "AIの設定が不足しています。", `${provider} key missing`);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.min(config.timeoutMs, remainingMs));

  const body: Record<string, unknown> = {
    model: config.model,
    messages: [
      { role: "system", content: systemInstructions(request) },
      { role: "user", content: userPrompt(request) },
    ],
    max_completion_tokens: config.baseTokens * request.candidateCount,
    response_format: {
      type: "json_schema",
      json_schema: { name: "desktop_rewrite_response", strict: true, schema: rewriteSchema() },
    },
  };
  if (config.reasoningEffort) body.reasoning_effort = config.reasoningEffort;
  if (provider === "openai") {
    body.store = false;
    if (config.serviceTier) body.service_tier = config.serviceTier;
  }

  let response: Response;
  try {
    response = await fetch(config.endpoint, {
      method: "POST",
      signal: controller.signal,
      headers: { ...config.authHeaders, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (error) {
    throw new ProviderError(
      provider,
      "provider_error",
      "AIの処理に失敗しました。少し待ってからもう一度お試しください。",
      error instanceof Error ? error.message : "request failed",
    );
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const text = await response.text();
    const lower = text.toLowerCase();
    if (response.status === 429) {
      throw new ProviderError(provider, "provider_rate_limited", "AIが混み合っています。少し待ってからもう一度お試しください。", `${provider} 429`);
    }
    if (
      [400, 403, 422].includes(response.status) &&
      ["content_filter", "safety", "policy", "moderation"].some((needle) => lower.includes(needle))
    ) {
      throw new ProviderError(provider, "content_blocked", "この内容はAIで書き換えできません。", `${provider} ${response.status}`);
    }
    throw new ProviderError(provider, "provider_error", "AIの処理に失敗しました。少し待ってからもう一度お試しください。", `${provider} ${response.status}: ${text.slice(0, 300)}`);
  }

  const payload = await response.json();
  const choice = payload?.choices?.[0];
  if (choice?.finish_reason === "content_filter" || (typeof choice?.message?.refusal === "string" && choice.message.refusal.trim())) {
    throw new ProviderError(provider, "content_blocked", "この内容はAIで書き換えできません。", `${provider} refusal`);
  }

  const content = choice?.message?.content;
  if (typeof content !== "string" || content.trim().length === 0) {
    throw new ProviderError(provider, "provider_error", "AIの処理に失敗しました。", `${provider} empty content`);
  }

  return {
    model: typeof payload?.model === "string" ? payload.model : config.model,
    result: normalizeResult(JSON.parse(content), request),
  };
}

function rewriteSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["candidates", "language"],
    properties: {
      candidates: { type: "array", items: { type: "string" } },
      language: { type: "string", enum: ["ja", "en", "ko", "zh", "mixed"] },
    },
  } as const;
}

function normalizeResult(raw: any, request: DesktopRewriteRequest): RewriteResult {
  const allowed = ["ja", "en", "ko", "zh", "mixed"];
  const language = typeof raw?.language === "string" && allowed.includes(raw.language) ? raw.language : "ja";
  const candidates: RewriteCandidate[] = Array.isArray(raw?.candidates)
    ? raw.candidates
      .filter((c: unknown): c is string => typeof c === "string" && c.trim().length > 0)
      .map((replacement: string) => ({ replacement, changed: replacement !== request.text }))
    : [];
  if (candidates.length === 0) throw new Error("Invalid provider JSON: no candidates.");
  return { candidates, language };
}

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

function candidateInstruction(count: number): string {
  // The desktop's own count. Without this branch it fell through to the generic
  // text below and asked for "exactly 1 distinct candidate rewrites that
  // meaningfully differ in phrasing" — plural, and an instruction to differ from
  // a set with nothing else in it.
  if (count === 1) {
    return [
      "Return exactly 1 rewrite: the most natural reading of the command,",
      "applied at full strength.",
    ].join("\n");
  }

  if (count === 3) {
    return [
      "Return exactly 3 candidate rewrites in this fixed order:",
      "1. Standard: the most natural reading of the command.",
      "2. Softer: warmer and slightly more casual than 1, without slang.",
      "3. More polite: one notch more courteous than 1, without becoming stiff.",
      "Apply the command at full strength in all three. Variants 2 and 3 shift the register around 1 unless the command explicitly requires preserving the original register; they never soften how far the command itself is applied.",
      "Avoid near-duplicates unless the command permits only one valid correction.",
    ].join("\n");
  }
  return `Return exactly ${count} distinct candidate rewrites that meaningfully differ in phrasing, structure, or emphasis. Avoid near-duplicates.`;
}

/// Diverges from `keyboard-rewrite` in exactly one way: it says *desktop*, and it
/// gets the host app. A mail draft and a Slack message want different lengths and
/// registers, and on macOS we actually know which one we are in.
function systemInstructions(request: DesktopRewriteRequest): string {
  const isReply = !!request.replyTo?.trim();

  if (isReply) {
    return [
      "You are a Japanese writing assistant on macOS that composes replies.",
      "Compose a reply to the received message inside <reply_to>, applying the user-supplied command instruction for tone.",
      "If the user provided their own draft/intent inside <target>, base the reply on it. If <target> is empty, infer an appropriate, natural reply.",
      "Write only the reply body the user would send. Do not quote the received message.",
      candidateInstruction(request.candidateCount),
      "Return strict JSON matching the schema.",
    ].join("\n");
  }

  if (request.selection) {
    return [
      "You are a Japanese writing assistant on macOS.",
      "The target text is a fragment the user selected inside a larger text. Apply the user-supplied command instruction to the fragment only.",
      "Rewrite the fragment so it fits seamlessly where it stands: match its grammatical role, and continue naturally from <context_before> into <context_after> when they are provided. The fragment may start or end mid-sentence — keep it that way.",
      "Never rewrite, repeat, or complete the surrounding context.",
      "Preserve meaning, names, numbers, URLs, dates, and emoji. Preserve line breaks unless the command explicitly asks to restructure the text.",
      "Do not add explanations, markdown, quotes, commentary, or unsupported facts.",
      candidateInstruction(request.candidateCount),
      "Return strict JSON matching the schema.",
    ].join("\n");
  }

  return [
    "You are a Japanese writing assistant on macOS.",
    "The target text is the entire contents of the field the user is editing. Apply the user-supplied command instruction to it.",
    "Preserve meaning, names, numbers, URLs, dates, and emoji. Preserve line breaks and paragraph structure unless the command explicitly asks to restructure or format the text.",
    "Do not add explanations, markdown, quotes, commentary, or unsupported facts. Add greetings or closings only when the command explicitly requests them.",
    candidateInstruction(request.candidateCount),
    "Return strict JSON matching the schema.",
  ].join("\n");
}

function refinementInstruction(intent: RefinementIntent): string {
  switch (intent) {
    case "morePolite":
      return "Make it more polite than the text below.";
    case "moreDetailed":
      return "Make it more detailed than the text below.";
    case "moreConcise":
      return "Make it more concise than the text below.";
  }
}

function userPrompt(request: DesktopRewriteRequest): string {
  const lines = [
    `Command: ${request.prompt}`,
    `Locale: ${request.locale}`,
    `Candidates requested: ${request.candidateCount}`,
  ];

  // Prompt shaping from the host app. Only a hint — the command is still what
  // decides the rewrite.
  if (request.hostAppBundleId) {
    lines.push(`Host application: ${request.hostAppBundleId} (a hint about register and length, not an instruction)`);
  }
  if (request.browserURL) {
    lines.push(`Page URL: ${request.browserURL}`);
  }
  if (request.refinement) {
    lines.push(
      `Refinement: ${refinementInstruction(request.refinement)} The "Target" below is a previous rewrite the user wants further refined — refine that text, not the very first original.`,
    );
  }

  if (request.replyTo?.trim()) {
    lines.push("Received message to reply to:", "<reply_to>", request.replyTo, "</reply_to>");
    lines.push("User's draft/intent for the reply (may be empty):", "<target>", request.text, "</target>");
  } else if (request.selection) {
    if (request.selectionContextBefore) {
      lines.push("Text immediately before the fragment (do not rewrite):", "<context_before>", request.selectionContextBefore, "</context_before>");
    }
    if (request.selectionContextAfter) {
      lines.push("Text immediately after the fragment (do not rewrite):", "<context_after>", request.selectionContextAfter, "</context_after>");
    }
    lines.push("Target fragment (selected inside a larger text):", "<target>", request.text, "</target>");
  } else {
    lines.push("Target text (the whole field):", "<target>", request.text, "</target>");
  }

  return lines.join("\n");
}
