export type DraftReadStatus =
  | "present"
  | "empty"
  | "unreadable"
  | "no_destination";

export type SourceBlock = {
  id: string;
  conversationId: string;
  text: string;
  order: number;
  role?: string;
  parentId?: string;
};

export type CapturedEvidence = {
  version: 1;
  snapshotId: string;
  blocks: SourceBlock[];
  status: "complete" | "partial" | "unavailable";
  truncationReasons: string[];
};

export type ParticipantEvidence = {
  blockId: string;
  kind: "sender_label" | "self_marker" | "account_identifier" | "profile_name";
};

export type ReplyParticipant = {
  id: string;
  label?: string;
  relationship: "self" | "other" | "unknown";
  evidence: ParticipantEvidence[];
};

export type ReplyMessage = {
  id: string;
  text: string;
  participantId?: string;
  sourceBlockIds: string[];
  order: number;
  kind: "message" | "quote";
  quotedByMessageId?: string;
  inReplyToMessageId?: string;
};

export type ReplyUncertainty = {
  kind:
    | "conversation"
    | "target"
    | "audience"
    | "speaker"
    | "quote_boundary"
    | "history";
  material: boolean;
  sourceBlockIds: string[];
};

export type ReplyContext = {
  version: 1;
  snapshotId: string;
  conversationId: string;
  sourceBlocks: SourceBlock[];
  participants: ReplyParticipant[];
  messages: ReplyMessage[];
  targetMessageIds: string[];
  audience: { kind: "direct" | "group" | "unknown"; participantIds: string[] };
  completeness: "complete" | "partial";
  uncertainties: ReplyUncertainty[];
};
