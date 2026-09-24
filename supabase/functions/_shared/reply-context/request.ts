import type { DraftReadStatus, ReplyContext } from "./types.ts";
import {
  ReplyContextError,
  requireWritableContext,
  selectedTargetText,
  validateReplyContext,
} from "./validate.ts";

type ReplyFields = {
  replyTo?: string | null;
  replyContext?: ReplyContext;
  draftReadStatus?: DraftReadStatus;
};

export function isReplyRequest(request: ReplyFields): boolean {
  return request.replyContext !== undefined || !!request.replyTo?.trim();
}

export function replySourceText(request: ReplyFields): string {
  return request.replyContext
    ? selectedTargetText(request.replyContext)
    : request.replyTo ?? "";
}

export function parseReplyFields(data: Record<string, unknown>): ReplyFields {
  const fail = (message: string): never => {
    throw new ReplyContextError("invalid_reply_context", message);
  };
  // Explicit null/malformed context must never fall through to compose.
  const hasContext = Object.hasOwn(data, "replyContext");
  if (hasContext && data.replyTo != null) {
    fail("Send replyContext or replyTo, not both.");
  }
  if (
    data.replyTo != null &&
    (typeof data.replyTo !== "string" || !data.replyTo.trim())
  ) {
    fail("replyTo must contain a message when supplied.");
  }
  const replyContext = hasContext
    ? validateReplyContext(data.replyContext)
    : undefined;
  if (replyContext) requireWritableContext(replyContext);
  const rawStatus = data.draftReadStatus;
  if (
    rawStatus !== undefined &&
    !["present", "empty", "unreadable", "no_destination"].includes(
      rawStatus as string,
    )
  ) {
    fail("Invalid draft read status.");
  }
  if (hasContext && rawStatus === undefined) {
    fail("Structured reply requires a draft read status.");
  }
  const draftReadStatus = rawStatus as DraftReadStatus | undefined;
  if (draftReadStatus) {
    if (!hasContext && data.replyTo == null) {
      fail("Draft read status is only valid for replies.");
    }
    if (typeof data.text !== "string") fail("Draft text must be a string.");
    if (
      draftReadStatus === "present"
        ? !(data.text as string).trim()
        : !!(data.text as string).trim()
    ) {
      fail("Draft text contradicts its read status.");
    }
  }
  return {
    replyTo: typeof data.replyTo === "string" ? data.replyTo : null,
    ...(replyContext ? { replyContext } : {}),
    ...(draftReadStatus ? { draftReadStatus } : {}),
  };
}
