import { parseCapture, parseResult, providerBody, geometryWarnings, type Capture } from "./contract.ts";
import { boundedBody, handle } from "./handler.ts";

function assert(v: unknown) { if (!v) throw new Error("assertion failed"); }
function rejects(fn: () => unknown) { let failed = false; try { fn(); } catch { failed = true; } assert(failed); }
const box = {x: 600, y: 100, width: 300, height: 200};
const capture: Capture = {captureId: "c", targetId: "right", intent: "Agree and mention the amount", appBundleId: "test",
  imageWidth: 1000, imageHeight: 800, composerBox: {x: 600, y: 700, width: 300, height: 80}, imageBase64: "/9j/AAAA"};
const result = {captureId: "c", targetId: "right", status: "ready", conversationRegion: [{label: "right", box}],
  evidence: [{excerpt: "Budget 7500", box, author: null, partial: false}], missingContext: [], draft: "Agreed: 7500."};

Deno.test("capture rejects URLs, clipped target, nonfinite and oversized images", () => {
  parseCapture(capture);
  rejects(() => parseCapture({...capture, imageBase64: "https://example.com/secret"}));
  rejects(() => parseCapture({...capture, composerBox: {...box, x: 999}}));
  rejects(() => parseCapture({...capture, composerBox: {...box, x: NaN}}));
  rejects(() => parseCapture({...capture, imageWidth: 100000}));
  rejects(() => parseCapture({...capture, intent: " "}));
  rejects(() => parseCapture({...capture, captureId: "../../escape"}));
});
Deno.test("response correlation, evidence and abstention validation", () => {
  parseResult(result, capture);
  for (const change of [{targetId: "left"}, {captureId: "old"}, {evidence: []}, {draft: " "},
    {status: "insufficient_context"}, {missingContext: ["missing opening"]},
    {evidence: [{...result.evidence[0], box: {...box, width: 1000}}]}]) {
    rejects(() => parseResult({...result, ...change}, capture));
  }
  parseResult({...result, evidence: [{excerpt: capture.intent, box: capture.composerBox, author: null, partial: false}]}, capture);
  parseResult({...result, status: "insufficient_context", draft: null, missingContext: ["missing opening"]}, capture);
});
Deno.test("slight and full evidence overlaps warn without discarding the reply", async () => {
  for (const evidenceBox of [{x: 600, y: 680, width: 300, height: 21}, capture.composerBox]) {
    const overlapping = {...result, evidence: [{...result.evidence[0], box: evidenceBox}]};
    const parsed = parseResult(overlapping, capture);
    assert(geometryWarnings(parsed, capture).length === 1);
    let calls = 0;
    const response = await handle(request(), env, () => Promise.resolve(Response.json(++calls === 1
      ? {email: "tester@example.test", email_confirmed_at: "now"}
      : {choices: [{finish_reason: "stop", message: {content: JSON.stringify(overlapping)}}]})));
    const data = await response.json();
    assert(response.status === 200 && data.result.draft === result.draft && data.geometryWarnings.length === 1);
    assert(data.validationVersion === "visual-intent-validation-2");
  }
  assert(geometryWarnings(parseResult(result, capture), capture).length === 0);
});
Deno.test("request sends one image and intent without a previous conversation", () => {
  const body = providerBody(capture, "pinned-model");
  assert(body.messages.length === 2 && body.store === false && body.reasoning_effort === "low");
  assert(JSON.stringify(body).includes("data:image/jpeg;base64,"));
  assert(JSON.stringify(body).includes(capture.intent));
});
Deno.test("streamed body limit applies without Content-Length", async () => {
  let failed = false;
  try { await boundedBody(new Request("https://test", {method: "POST", body: "x".repeat(101)}), 100); }
  catch { failed = true; }
  assert(failed);
});
Deno.test("unauthenticated request does not reach provider", async () => {
  const response = await handle(new Request("https://test", {method: "POST", body: "{}"}));
  assert(response.status === 401);
});

const env = (key: string) => ({VISUAL_INTENT_TESTER_EMAILS: "tester@example.test", SUPABASE_URL: "https://auth.test",
  SUPABASE_ANON_KEY: "public", OPENAI_API_KEY: "test-only"} as Record<string, string>)[key];
const request = () => new Request("https://test", {method: "POST", headers: {Authorization: "Bearer test-only"}, body: JSON.stringify(capture)});
Deno.test("disabled research makes no outbound request", async () => {
  const response = await handle(request(), () => undefined, () => { throw new Error("must not fetch"); });
  assert(response.status === 503);
});
Deno.test("unconfirmed or non-tester account cannot send image to provider", async () => {
  for (const user of [{email: "other@example.test", email_confirmed_at: "now"}, {email: "tester@example.test"}]) {
    let calls = 0;
    const response = await handle(request(), env, () => { calls++; return Promise.resolve(Response.json(user)); });
    assert(calls === 1 && response.status === 403);
  }
});
Deno.test("authorized full request validates result and exposes usage without raw provider payload", async () => {
  let calls = 0;
  const response = await handle(request(), env, (_url, init) => {
    calls++;
    if (calls === 1) return Promise.resolve(Response.json({email: "tester@example.test", email_confirmed_at: "now"}));
    const body = JSON.parse(init?.body as string);
    assert(body.model === "gpt-6-luna" && body.reasoning_effort === "low");
    assert(!("temperature" in body) && !("top_p" in body));
    return Promise.resolve(Response.json({model: body.model, choices: [{finish_reason: "stop", message: {content: JSON.stringify(result)}}],
      usage: {prompt_tokens: 100, completion_tokens: 50}}));
  });
  const data = await response.json();
  assert(response.status === 200 && calls === 2 && data.result.targetId === "right" && data.inputTokens === 100 && !data.choices);
  assert(data.reasoningEffort === "low" && data.promptVersion === "visual-intent-a-4");
});
Deno.test("provider truncation fails instead of returning partial draft", async () => {
  let calls = 0;
  const response = await handle(request(), env, () => Promise.resolve(Response.json(++calls === 1
    ? {email: "tester@example.test", email_confirmed_at: "now"}
    : {choices: [{finish_reason: "length", message: {content: JSON.stringify(result)}}]})));
  assert(response.status === 502);
});
