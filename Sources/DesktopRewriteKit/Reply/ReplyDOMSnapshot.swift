import Foundation

/// Browser identities stay in TextIO. Only structural, opaque evidence reaches the service.
public struct ReplyDOMSnapshot: Codable, Equatable, Sendable {
    public let source: String
    public let adapter: String
    public let revision: String
    public let conversationId: String
    public let composerId: String
    public let headerBlockIds: [String]
    public let messages: [ReplyDOMMessage]
    public let coverage: [String]

    public func scoped(to id: String) -> Self? { id == conversationId ? self : nil }
}

public struct ReplyDOMMessage: Codable, Equatable, Sendable {
    public let id: String
    public let bodyBlockIds: [String]
    public let senderBlockId: String?
    public let timestampBlockId: String?
    public let quoteBlockIds: [String]
    public let order: Int
    public let visibility: String
    public let coverage: String
}
