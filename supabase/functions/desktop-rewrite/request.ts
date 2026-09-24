import type {
  DraftReadStatus,
  ReplyContext,
} from "../_shared/reply-context/types.ts";
import { ReplyContextError } from "../_shared/reply-context/validate.ts";
import {
  isReplyRequest,
  parseReplyFields,
} from "../_shared/reply-context/request.ts";

type CaptureMode = "wholeInput" | "selection" | "fullDocument";
type RefinementIntent = "morePolite" | "moreDetailed" | "moreConcise";

export type DesktopRewriteRequest = {
  prompt: string;
  text: string;
  replyTo?: string | null;
  replyContext?: ReplyContext;
  draftReadStatus?: DraftReadStatus;
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
  /// 'ja' | 'en' — the language the user's BUTTONS write in, which is not the
  /// interface language: a 简体中文 user reads Chinese and writes Japanese, so they
  /// send 'ja'. Absent on every build older than this field, and absent must keep
  /// those users' output identical — `systemInstructions` treats anything but 'en'
  /// as Japanese for exactly that reason.
  writingLanguage?: "ja" | "en" | null;
  /// 'ax' | 'clipboard'. Only the client knows which path it actually used, and
  /// §7 makes this the earliest signal that an app's AX tree changed — so it has
  /// to come over the wire or the column is permanently null.
  ioPath?: "ax" | "clipboard" | null;
  /// A client-generated UUID, unique per USER INTENT and carried through
  /// reserve → commit → release. `docs/billing.md` §6 makes it the idempotency key:
  /// a client retry of the same rewrite returns the existing reservation and
  /// cannot consume quota twice (§9 row 29).
  requestId: string;
  /// The same UUID `RewriteAttempt.id` sends to PostHog as `attempt_id` — carried
  /// over so `desktop.rewrite_events` can be joined to PostHog without guessing.
  attemptId?: string | null;
  /// `RewriteType.rawValue` (saved_button/custom_instruction/reply/regenerate/
  /// refine) — replaces "is commandKey nil" as the signal for what kind of
  /// interaction this was.
  rewriteType?: string | null;
  /// The privacy-safe saved-button label already computed for PostHog's
  /// button_key (e.g. "Shorten", "Client message") — richer than commandKey.
  buttonAnalyticsKey?: string | null;
  /// The server eventId of the attempt a regenerate/refine followed.
  previousEventId?: string | null;
};

const MIN_CANDIDATES = 1;
const MAX_CANDIDATES = 5;
const DEFAULT_CANDIDATES = 3;

export function parseRequest(
  body: unknown,
  jsonError: (code: string, message: string, status: number) => Response = (
    code,
    message,
    status,
  ) => Response.json({ error: code, message }, { status }),
): { value: DesktopRewriteRequest } | { error: Response } {
  if (!body || typeof body !== "object") {
    return {
      error: jsonError(
        "invalid_request",
        "Request body must be an object.",
        400,
      ),
    };
  }
  const data = body as Record<string, unknown>;

  let replyFields: ReturnType<typeof parseReplyFields>;
  try {
    replyFields = parseReplyFields(data);
  } catch (error) {
    if (!(error instanceof ReplyContextError)) throw error;
    return { error: jsonError(error.code, error.message, 400) };
  }

  if (
    typeof data.prompt !== "string" ||
    (!isReplyRequest(replyFields) && data.prompt.trim().length === 0)
  ) {
    return {
      error: jsonError("invalid_request", "`prompt` is required.", 400),
    };
  }
  if (typeof data.text !== "string") {
    return { error: jsonError("invalid_request", "`text` is required.", 400) };
  }

  const captureMode = data.captureMode;
  if (
    captureMode !== "wholeInput" && captureMode !== "selection" &&
    captureMode !== "fullDocument"
  ) {
    return {
      error: jsonError("invalid_request", "`captureMode` is invalid.", 400),
    };
  }

  const rawCount = typeof data.candidateCount === "number" &&
      Number.isFinite(data.candidateCount)
    ? data.candidateCount
    : DEFAULT_CANDIDATES;
  const candidateCount = Math.min(
    MAX_CANDIDATES,
    Math.max(MIN_CANDIDATES, Math.floor(rawCount)),
  );

  const optionalString = (value: unknown): string | null =>
    typeof value === "string" && value.length > 0 ? value : null;

  return {
    value: {
      prompt: data.prompt,
      text: data.text,
      ...replyFields,
      commandKey: optionalString(data.commandKey),
      title: optionalString(data.title),
      promptOrigin: optionalString(data.promptOrigin),
      locale: typeof data.locale === "string" ? data.locale : "ja-JP",
      appVersion: typeof data.appVersion === "string"
        ? data.appVersion
        : "unknown",
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
      // `"ja"` is preserved rather than collapsed to null, and only because the
      // value is logged now: null used to mean "en was not requested", which is the
      // same thing `systemInstructions` still reads it as, but on the event row it
      // would conflate a 简体中文 user's deliberate 'ja' with a build too old to have
      // the field. Every consumer tests for `=== "en"` or `!== "en"`, so widening
      // this changes no prompt.
      writingLanguage: data.writingLanguage === "en"
        ? "en"
        : data.writingLanguage === "ja"
        ? "ja"
        : null,
      ioPath: data.ioPath === "ax" || data.ioPath === "clipboard"
        ? data.ioPath
        : null,
      // A generated fallback keeps a pre-billing client working, and it degrades in
      // the only direction that is safe: without a stable id a retry reserves twice
      // rather than reusing one reservation, so the user is protected and the
      // duplicate is bounded by the 5-minute reservation TTL.
      requestId: typeof data.requestId === "string" && data.requestId.length > 0
        ? data.requestId.slice(0, 100)
        : crypto.randomUUID(),
      attemptId: optionalString(data.attemptId),
      rewriteType: optionalString(data.rewriteType),
      buttonAnalyticsKey: optionalString(data.buttonAnalyticsKey),
      previousEventId: optionalString(data.previousEventId),
    },
  };
}
