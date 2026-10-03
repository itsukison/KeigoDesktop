import { parseCapture, parseResult, promptVersion, providerBody, geometryWarnings, validationVersion, reasoningEffort } from "./contract.ts";

const json = (body: unknown, status = 200) => Response.json(body, {status, headers: {"Cache-Control": "no-store"}});
const failure = (code: string, message: string, status: number) => json({error: {code, message}}, status);

export async function boundedBody(req: Request, max = 11_000_000): Promise<unknown> {
  if (Number(req.headers.get("content-length")) > max) throw new Error("body_too_large");
  const reader = req.body?.getReader();
  if (!reader) throw new Error("missing_body");
  let size = 0; const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.length;
      if (size > max) { await reader.cancel(); throw new Error("body_too_large"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

// A research-only endpoint: disabled unless an operator explicitly names testers.
// Auth is verified again through Auth, even when gateway validation is enabled.
export async function handle(req: Request, env: (name: string) => string | undefined = Deno.env.get,
                             request: typeof fetch = fetch): Promise<Response> {
  if (req.method !== "POST") return failure("method", "POST required.", 405);
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return failure("unauthorized", "Sign in to KeigoButton first.", 401);
  const allowed = (env("VISUAL_INTENT_TESTER_EMAILS") ?? "").toLowerCase().split(",").map(s => s.trim()).filter(Boolean);
  if (!allowed.length) return failure("research_disabled", "The visual research endpoint has no enabled test accounts.", 503);
  try {
    const userResponse = await request(`${env("SUPABASE_URL")}/auth/v1/user`, {
      headers: {Authorization: authorization, apikey: env("SUPABASE_ANON_KEY") ?? ""},
      signal: AbortSignal.timeout(8000),
    });
    if (!userResponse.ok) return failure("unauthorized", "Sign in to KeigoButton first.", 401);
    const user = await userResponse.json();
    if (!user.email_confirmed_at || !allowed.includes(String(user.email ?? "").toLowerCase())) {
      return failure("research_forbidden", "This account is not enabled for visual research.", 403);
    }
  } catch { return failure("auth_unavailable", "Could not verify the research account.", 503); }
  let capture;
  try { capture = parseCapture(await boundedBody(req)); }
  catch { return failure("invalid_capture", "Invalid or oversized capture.", 400); }
  const key = env("OPENAI_API_KEY");
  if (!key) return failure("provider_unavailable", "Research model is not configured.", 503);
  const model = "gpt-6-luna";
  const start = performance.now();
  try {
    const response = await request("https://api.openai.com/v1/chat/completions", {
      method: "POST", headers: {Authorization: `Bearer ${key}`, "Content-Type": "application/json"},
      body: JSON.stringify(providerBody(capture, model)), signal: AbortSignal.timeout(35000),
    });
    if (!response.ok) return failure("provider_error", `Research provider returned HTTP ${response.status}.`, 502);
    const payload = await response.json();
    const choice = payload.choices?.[0];
    if (choice?.finish_reason !== "stop" || choice?.message?.refusal) throw new Error("incomplete_result");
    const result = parseResult(JSON.parse(choice.message.content), capture);
    return json({result, model: payload.model ?? model, reasoningEffort, promptVersion, validationVersion,
      geometryWarnings: geometryWarnings(result, capture), modelMs: Math.round(performance.now() - start),
      inputTokens: payload.usage?.prompt_tokens ?? null, outputTokens: payload.usage?.completion_tokens ?? null});
  } catch (error) {
    const reason = error instanceof Error && ["invalid_model_result", "incomplete_result"].includes(error.message)
      ? error.message : error instanceof SyntaxError ? "invalid_json" : "provider_request_failed";
    return failure(reason, `Research result rejected: ${reason}.`, 502);
  }
}
