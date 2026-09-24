import {
  MAX_CONTEXT_TEXT,
  ReplyContextError,
  requireWritableContext,
  selectedTargetText,
  validateCapturedEvidence,
  validateReplyContext,
} from "./validate.ts";
import type { ReplyContext } from "./types.ts";

export function fixture(name: string): unknown {
  return JSON.parse(
    Deno.readTextFileSync(
      new URL(
        `../../../../Tests/Fixtures/ReplyContext/${name}.json`,
        import.meta.url,
      ),
    ),
  );
}

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

function rejects(work: () => unknown, code = "invalid_reply_context") {
  try {
    work();
  } catch (error) {
    assert(
      error instanceof ReplyContextError && error.code === code,
      String(error),
    );
    return;
  }
  throw new Error("Expected rejection");
}

Deno.test("shared direct, group and quote fixtures preserve exact source and unknown identity", () => {
  for (const name of ["direct-ja", "group-en", "quoted-zh", "ambiguous"]) {
    const raw = fixture(name);
    const context = validateReplyContext(raw);
    assert(JSON.stringify(context) !== "");
    assert(
      context.messages.every((m) =>
        m.text ===
          context.sourceBlocks.filter((b) => m.sourceBlockIds.includes(b.id))
            .map((b) => b.text).join("\n")
      ),
    );
    if (name !== "ambiguous") requireWritableContext(context);
  }
  const group = validateReplyContext(fixture("group-en"));
  assert(
    group.participants.length === 2 &&
      group.participants.every((p) =>
        p.label === "Alex" && p.relationship === "unknown"
      ),
  );
  assert(group.messages[2].participantId === undefined);
  assert(
    selectedTargetText(group) === "Alex (Design): Can you review the mockups?",
  );
  assert(
    validateReplyContext(fixture("quoted-zh")).messages[1].participantId ===
      undefined,
  );
});

Deno.test("ambiguous context is representable but cannot reach the writer", () => {
  const context = validateReplyContext(fixture("ambiguous"));
  rejects(() => requireWritableContext(context), "reply_context_needs_choice");
});

Deno.test("capture keeps separate conversations and explicit truncation", () => {
  const evidence = validateCapturedEvidence(fixture("captured-two-threads"));
  assert(
    evidence.status === "partial" &&
      new Set(evidence.blocks.map((b) => b.conversationId)).size === 2,
  );
  rejects(() => validateCapturedEvidence({ ...evidence, status: "complete" }));
  rejects(() => validateCapturedEvidence({ ...evidence, version: 2 }));
  rejects(() =>
    validateCapturedEvidence({
      ...evidence,
      blocks: evidence.blocks.map((b) => ({ ...b, parentId: b.id })),
    })
  );
});

Deno.test("malformed or invented references and unsupported versions are rejected", () => {
  rejects(() => validateReplyContext(fixture("invalid-reference")));
  for (const value of [null, [], {}, { version: 2 }]) {
    rejects(() => validateReplyContext(value));
  }
});

const mutations: [string, (c: ReplyContext) => void][] = [
  ["invented text", (c) => {
    c.messages[1].text = "I accept";
  }],
  ["unknown source", (c) => {
    c.messages[1].sourceBlockIds = ["missing"];
  }],
  ["duplicate message", (c) => {
    c.messages.push(c.messages[0]);
  }],
  ["reused source", (c) => {
    c.messages.push({ ...c.messages[0], id: "m3" });
  }],
  ["unknown target", (c) => {
    c.targetMessageIds = ["missing"];
  }],
  ["empty target", (c) => {
    c.targetMessageIds = [];
  }],
  ["unknown recipient", (c) => {
    c.audience.participantIds = ["missing"];
  }],
  ["self recipient", (c) => {
    c.audience.participantIds = ["self"];
  }],
  ["name alone proves self", (c) => {
    c.participants[0].evidence[0].kind = "profile_name";
  }],
  ["sender label proves self", (c) => {
    c.participants[0].evidence[0].kind = "sender_label";
  }],
  ["mixed conversations", (c) => {
    c.sourceBlocks[0].conversationId = "other-thread";
  }],
  ["fabricated chronology", (c) => {
    c.messages[0].order = 50;
  }],
  ["cyclic reply", (c) => {
    c.messages[0].inReplyToMessageId = "m2";
  }],
  ["quote without container", (c) => {
    c.messages[0].kind = "quote";
  }],
  ["non-material target uncertainty", (c) => {
    c.uncertainties.push({
      kind: "target",
      material: false,
      sourceBlockIds: [],
    });
  }],
  ["aggregate oversized source", (c) => {
    c.sourceBlocks.forEach((b) => {
      b.text = "x".repeat(MAX_CONTEXT_TEXT);
    });
  }],
];
for (const [name, mutate] of mutations) {
  Deno.test(`context rejects ${name}`, () => {
    const context = validateReplyContext(fixture("direct-ja"));
    mutate(context);
    rejects(() => validateReplyContext(context));
  });
}

Deno.test("reply may target self-authored history and more than one message without changing authors", () => {
  const context = validateReplyContext(fixture("direct-ja"));
  context.targetMessageIds = ["m2", "m1"];
  const parsed = validateReplyContext(context);
  requireWritableContext(parsed);
  assert(
    selectedTargetText(parsed) ===
      context.messages.map((m) => m.text).join("\n\n"),
  );
});
