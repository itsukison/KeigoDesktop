import Foundation

// Desktop-only v1 wire models. Runtime validation is enforced by the backend.
// Shared JSON fixtures in Tests/Fixtures/ReplyContext pin cross-runtime parity.

public enum ReplyDraftReadStatus: String, Codable, Equatable, Sendable {
    case present
    case empty
    case unreadable
    case noDestination = "no_destination"
}

public enum ReplyCaptureStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case unavailable
}

public enum ReplyEvidenceKind: String, Codable, Equatable, Sendable {
    case senderLabel = "sender_label"
    case selfMarker = "self_marker"
    case accountIdentifier = "account_identifier"
    case profileName = "profile_name"
}

public enum ReplyParticipantRelationship: String, Codable, Equatable, Sendable {
    case `self`
    case other
    case unknown
}

public enum ReplyMessageKind: String, Codable, Equatable, Sendable {
    case message
    case quote
}

public enum ReplyAudienceKind: String, Codable, Equatable, Sendable {
    case direct
    case group
    case unknown
}

public enum ReplyUncertaintyKind: String, Codable, Equatable, Sendable {
    case conversation
    case target
    case audience
    case speaker
    case quoteBoundary = "quote_boundary"
    case history
}

public enum ReplyCompleteness: String, Codable, Equatable, Sendable {
    case complete
    case partial
}

public struct ReplySourceBlock: Codable, Equatable, Sendable {
    public let id: String
    public let conversationId: String
    public let text: String
    public let order: Int
    public let role: String?
    public let parentId: String?

    public init(
        id: String,
        conversationId: String,
        text: String,
        order: Int,
        role: String? = nil,
        parentId: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.text = text
        self.order = order
        self.role = role
        self.parentId = parentId
    }
}

public struct CapturedReplyEvidence: Codable, Equatable, Sendable {
    public let version: Int
    public let snapshotId: String
    public let blocks: [ReplySourceBlock]
    public let status: ReplyCaptureStatus
    public let truncationReasons: [String]

    public init(
        version: Int = 1,
        snapshotId: String,
        blocks: [ReplySourceBlock],
        status: ReplyCaptureStatus,
        truncationReasons: [String]
    ) {
        self.version = version
        self.snapshotId = snapshotId
        self.blocks = blocks
        self.status = status
        self.truncationReasons = truncationReasons
    }
}

public struct ReplyParticipantEvidence: Codable, Equatable, Sendable {
    public let blockId: String
    public let kind: ReplyEvidenceKind

    public init(
        blockId: String,
        kind: ReplyEvidenceKind
    ) {
        self.blockId = blockId
        self.kind = kind
    }
}

public struct ReplyParticipant: Codable, Equatable, Sendable {
    public let id: String
    public let label: String?
    public let relationship: ReplyParticipantRelationship
    public let evidence: [ReplyParticipantEvidence]

    public init(
        id: String,
        label: String? = nil,
        relationship: ReplyParticipantRelationship,
        evidence: [ReplyParticipantEvidence]
    ) {
        self.id = id
        self.label = label
        self.relationship = relationship
        self.evidence = evidence
    }
}

public struct ReplyMessage: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let participantId: String?
    public let sourceBlockIds: [String]
    public let order: Int
    public let kind: ReplyMessageKind
    public let quotedByMessageId: String?
    public let inReplyToMessageId: String?

    public init(
        id: String,
        text: String,
        participantId: String? = nil,
        sourceBlockIds: [String],
        order: Int,
        kind: ReplyMessageKind,
        quotedByMessageId: String? = nil,
        inReplyToMessageId: String? = nil
    ) {
        self.id = id
        self.text = text
        self.participantId = participantId
        self.sourceBlockIds = sourceBlockIds
        self.order = order
        self.kind = kind
        self.quotedByMessageId = quotedByMessageId
        self.inReplyToMessageId = inReplyToMessageId
    }
}

public struct ReplyAudience: Codable, Equatable, Sendable {
    public let kind: ReplyAudienceKind
    public let participantIds: [String]

    public init(
        kind: ReplyAudienceKind,
        participantIds: [String]
    ) {
        self.kind = kind
        self.participantIds = participantIds
    }
}

public struct ReplyUncertainty: Codable, Equatable, Sendable {
    public let kind: ReplyUncertaintyKind
    public let material: Bool
    public let sourceBlockIds: [String]

    public init(
        kind: ReplyUncertaintyKind,
        material: Bool,
        sourceBlockIds: [String]
    ) {
        self.kind = kind
        self.material = material
        self.sourceBlockIds = sourceBlockIds
    }
}

public struct ReplyContext: Codable, Equatable, Sendable {
    public let version: Int
    public let snapshotId: String
    public let conversationId: String
    public let sourceBlocks: [ReplySourceBlock]
    public let participants: [ReplyParticipant]
    public let messages: [ReplyMessage]
    public let targetMessageIds: [String]
    public let audience: ReplyAudience
    public let completeness: ReplyCompleteness
    public let uncertainties: [ReplyUncertainty]

    public init(
        version: Int = 1,
        snapshotId: String,
        conversationId: String,
        sourceBlocks: [ReplySourceBlock],
        participants: [ReplyParticipant],
        messages: [ReplyMessage],
        targetMessageIds: [String],
        audience: ReplyAudience,
        completeness: ReplyCompleteness,
        uncertainties: [ReplyUncertainty]
    ) {
        self.version = version
        self.snapshotId = snapshotId
        self.conversationId = conversationId
        self.sourceBlocks = sourceBlocks
        self.participants = participants
        self.messages = messages
        self.targetMessageIds = targetMessageIds
        self.audience = audience
        self.completeness = completeness
        self.uncertainties = uncertainties
    }

    public var selectedTargetText: String {
        let targets = Set(targetMessageIds)
        return messages.filter { targets.contains($0.id) }
            .sorted { $0.order < $1.order }
            .map(\.text)
            .joined(separator: "\n\n")
    }
}
