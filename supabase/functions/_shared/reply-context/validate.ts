import type { CapturedEvidence, ReplyContext, SourceBlock } from "./types.ts";

export const MAX_CONTEXT_TEXT = 12000;
const MAX_JSON_BYTES = 96000;

export class ReplyContextError extends Error {
  constructor(
    public readonly code:
      | "invalid_reply_context"
      | "reply_context_needs_choice",
    message: string,
  ) {
    super(message);
  }
}

function check(value: unknown, message: string): asserts value {
  if (!value) throw new ReplyContextError("invalid_reply_context", message);
}

function object(value: unknown): Record<string, unknown> {
  check(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "Expected an object.",
  );
  return value as Record<string, unknown>;
}

function keys(value: Record<string, unknown>, allowed: string[]): void {
  check(
    Object.keys(value).every((key) => allowed.includes(key)),
    "Unsupported context field.",
  );
}

function list(value: unknown, max: number): unknown[] {
  check(
    Array.isArray(value) && value.length <= max,
    "Invalid or oversized list.",
  );
  return value;
}

function string(value: unknown, max: number, nonempty = true): string {
  check(
    typeof value === "string" && value.length <= max &&
      (!nonempty || value.trim().length > 0),
    "Invalid string.",
  );
  return value;
}

function id(value: unknown): string {
  const result = string(value, 80);
  check(/^[a-zA-Z0-9_-]+$/.test(result), "Invalid identifier.");
  return result;
}

function choice<T extends string>(value: unknown, allowed: readonly T[]): T {
  check(
    typeof value === "string" && allowed.includes(value as T),
    "Invalid enum value.",
  );
  return value as T;
}

function order(value: unknown): number {
  check(
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0,
    "Invalid observed order.",
  );
  return value;
}

function unique<T>(values: T[]): T[] {
  check(
    new Set(values).size === values.length,
    "Duplicate identifier or order.",
  );
  return values;
}

function references(value: unknown, valid: Set<string>, max: number): string[] {
  const result = unique(list(value, max).map(id));
  check(result.every((item) => valid.has(item)), "Unknown evidence reference.");
  return result;
}

function bounded(value: unknown): void {
  const serialized = JSON.stringify(value);
  check(
    typeof serialized === "string" &&
      new TextEncoder().encode(serialized).length <= MAX_JSON_BYTES,
    "Context payload too large.",
  );
}

function blocks(value: unknown): SourceBlock[] {
  let chars = 0;
  const result = list(value, 200).map((raw) => {
    const b = object(raw);
    keys(b, ["id", "conversationId", "text", "order", "role", "parentId"]);
    const text = string(b.text, MAX_CONTEXT_TEXT, false);
    chars += text.length;
    return {
      id: id(b.id),
      conversationId: id(b.conversationId),
      text,
      order: order(b.order),
      ...(b.role === undefined ? {} : { role: string(b.role, 100) }),
      ...(b.parentId === undefined ? {} : { parentId: id(b.parentId) }),
    };
  });
  check(chars <= MAX_CONTEXT_TEXT, "Aggregate source text too large.");
  const ids = new Set(unique(result.map((b) => b.id)));
  unique(result.map((b) => b.order));
  for (const b of result) {
    const seen = new Set([b.id]);
    let parent = b.parentId;
    while (parent !== undefined) {
      check(
        ids.has(parent) && !seen.has(parent),
        "Invalid or cyclic parent reference.",
      );
      seen.add(parent);
      const p = result.find((item) => item.id === parent)!;
      check(
        p.conversationId === b.conversationId,
        "Parent belongs to another conversation.",
      );
      parent = p.parentId;
    }
  }
  return result;
}

export function validateCapturedEvidence(value: unknown): CapturedEvidence {
  bounded(value);
  const v = object(value);
  keys(v, ["version", "snapshotId", "blocks", "status", "truncationReasons"]);
  check(v.version === 1, "Unsupported evidence version.");
  const status = choice(v.status, ["complete", "partial", "unavailable"]);
  const source = blocks(v.blocks);
  const reasons = list(v.truncationReasons, 10).map((r) => string(r, 100));
  check(
    status !== "complete" || reasons.length === 0,
    "Complete capture cannot be truncated.",
  );
  check(
    status !== "complete" || source.length > 0,
    "Complete capture cannot be empty.",
  );
  return {
    version: 1,
    snapshotId: id(v.snapshotId),
    blocks: source,
    status,
    truncationReasons: reasons,
  };
}

// Validates structure and evidence references, not the truth of model-assigned roles.
export function validateReplyContext(value: unknown): ReplyContext {
  bounded(value);
  const v = object(value);
  keys(v, [
    "version",
    "snapshotId",
    "conversationId",
    "sourceBlocks",
    "participants",
    "messages",
    "targetMessageIds",
    "audience",
    "completeness",
    "uncertainties",
  ]);
  check(v.version === 1, "Unsupported reply context version.");
  const conversationId = id(v.conversationId);
  const sourceBlocks = blocks(v.sourceBlocks);
  check(
    sourceBlocks.length > 0 &&
      sourceBlocks.every((b) => b.conversationId === conversationId),
    "Context must contain one selected conversation.",
  );
  const sourceIds = new Set(sourceBlocks.map((b) => b.id));
  const participants = list(v.participants, 30).map((raw) => {
    const p = object(raw);
    keys(p, ["id", "label", "relationship", "evidence"]);
    const relationship = choice(p.relationship, ["self", "other", "unknown"]);
    const evidence = list(p.evidence, 20).map((rawEvidence) => {
      const e = object(rawEvidence);
      keys(e, ["blockId", "kind"]);
      const blockId = id(e.blockId);
      check(sourceIds.has(blockId), "Unknown participant evidence.");
      return {
        blockId,
        kind: choice(e.kind, [
          "sender_label",
          "self_marker",
          "account_identifier",
          "profile_name",
        ]),
      };
    });
    if (relationship !== "unknown") {
      check(
        evidence.some((e) => e.kind !== "profile_name"),
        "A profile name alone cannot establish identity.",
      );
    }
    if (relationship === "self") {
      check(
        evidence.some((e) =>
          e.kind === "self_marker" || e.kind === "account_identifier"
        ),
        "Self identity needs explicit evidence.",
      );
    }
    return {
      id: id(p.id),
      ...(p.label === undefined ? {} : { label: string(p.label, 200) }),
      relationship,
      evidence,
    };
  });
  check(
    participants.filter((p) => p.relationship === "self").length <= 1,
    "Conflicting self identities.",
  );
  const participantIds = new Set(unique(participants.map((p) => p.id)));
  const usedBlocks = new Set<string>();
  const messages = list(v.messages, 100).map((raw) => {
    const m = object(raw);
    keys(m, [
      "id",
      "text",
      "participantId",
      "sourceBlockIds",
      "order",
      "kind",
      "quotedByMessageId",
      "inReplyToMessageId",
    ]);
    const sourceBlockIds = references(m.sourceBlockIds, sourceIds, 200);
    check(sourceBlockIds.length > 0, "Message requires source evidence.");
    const source = sourceBlockIds.map((ref) =>
      sourceBlocks.find((b) => b.id === ref)!
    );
    check(
      source.every((b, i) => i === 0 || source[i - 1].order < b.order),
      "Message source order changed.",
    );
    for (const ref of sourceBlockIds) {
      check(!usedBlocks.has(ref), "Source text reused as multiple messages.");
      usedBlocks.add(ref);
    }
    const text = string(m.text, MAX_CONTEXT_TEXT);
    check(
      text === source.map((b) => b.text).join("\n"),
      "Message text differs from source evidence.",
    );
    const messageOrder = order(m.order);
    check(
      messageOrder === source[0].order,
      "Message order differs from source evidence.",
    );
    const participantId = m.participantId === undefined
      ? undefined
      : id(m.participantId);
    check(
      participantId === undefined || participantIds.has(participantId),
      "Unknown message participant.",
    );
    return {
      id: id(m.id),
      text,
      sourceBlockIds,
      order: messageOrder,
      kind: choice(m.kind, ["message", "quote"]),
      ...(participantId === undefined ? {} : { participantId }),
      ...(m.quotedByMessageId === undefined
        ? {}
        : { quotedByMessageId: id(m.quotedByMessageId) }),
      ...(m.inReplyToMessageId === undefined
        ? {}
        : { inReplyToMessageId: id(m.inReplyToMessageId) }),
    };
  });
  const messageIds = new Set(unique(messages.map((m) => m.id)));
  for (const m of messages) {
    for (const ref of [m.quotedByMessageId, m.inReplyToMessageId]) {
      check(
        ref === undefined || (messageIds.has(ref) && ref !== m.id),
        "Unknown or self-referential message relationship.",
      );
    }
    check(
      m.kind === "quote"
        ? m.quotedByMessageId !== undefined
        : m.quotedByMessageId === undefined,
      "Quote must reference its containing message.",
    );
    if (m.quotedByMessageId) {
      check(
        messages.find((p) => p.id === m.quotedByMessageId)?.kind === "message",
        "Quote container must be a message.",
      );
    }
    if (m.inReplyToMessageId) {
      check(
        messages.find((p) => p.id === m.inReplyToMessageId)!.order < m.order,
        "Reply relationship contradicts observed order.",
      );
    }
  }
  const targetMessageIds = references(v.targetMessageIds, messageIds, 100);
  check(targetMessageIds.length > 0, "At least one reply target is required.");
  const a = object(v.audience);
  keys(a, ["kind", "participantIds"]);
  const audience = {
    kind: choice(a.kind, ["direct", "group", "unknown"]),
    participantIds: references(a.participantIds, participantIds, 30),
  };
  check(
    !audience.participantIds.some((ref) =>
      participants.find((p) => p.id === ref)?.relationship === "self"
    ),
    "Reply audience cannot include self.",
  );
  check(
    audience.kind !== "direct" || audience.participantIds.length <= 1,
    "Direct audience cannot have multiple recipients.",
  );
  check(
    audience.kind !== "unknown" || audience.participantIds.length === 0,
    "Unknown audience cannot assert recipients.",
  );
  const uncertainties = list(v.uncertainties, 30).map((raw) => {
    const u = object(raw);
    keys(u, ["kind", "material", "sourceBlockIds"]);
    check(
      typeof u.material === "boolean",
      "Uncertainty must declare materiality.",
    );
    const kind = choice(u.kind, [
      "conversation",
      "target",
      "audience",
      "speaker",
      "quote_boundary",
      "history",
    ]);
    check(
      !["conversation", "target", "audience"].includes(kind) || u.material,
      "Selection uncertainty must be material.",
    );
    return {
      kind,
      material: u.material,
      sourceBlockIds: references(u.sourceBlockIds, sourceIds, 200),
    };
  });
  return {
    version: 1,
    snapshotId: id(v.snapshotId),
    conversationId,
    sourceBlocks,
    participants,
    messages,
    targetMessageIds,
    audience,
    completeness: choice(v.completeness, ["complete", "partial"]),
    uncertainties,
  };
}

export function requireWritableContext(context: ReplyContext): void {
  if (
    context.uncertainties.some((u) => u.material) ||
    context.audience.kind === "unknown"
  ) {
    throw new ReplyContextError(
      "reply_context_needs_choice",
      "Choose the conversation or reply audience before generating.",
    );
  }
}

export function selectedTargetText(context: ReplyContext): string {
  const targets = new Set(context.targetMessageIds);
  return context.messages.filter((m) => targets.has(m.id)).sort((a, b) =>
    a.order - b.order
  ).map((m) => m.text).join("\n\n");
}
