import Foundation
import DesktopRewriteKit

public struct ReplyCaptureResult: Sendable {
    public let evidence: CapturedReplyEvidence
    public let binding: BrowserReplyBinding?
    public let source: String
    public let fallbackReason: String?
    public let failureReason: String?
    public let observations: [ReplyNodeObservation]
}

public actor ReplyCaptureCoordinator {
    public nonisolated let browser = BrowserReplyBridge()
    private let ax = AXConversationReader()
    public init() {}
    public static func permitsAXFallback(_ reason: String) -> Bool {
        ["extension_unavailable", "permission_missing", "unsupported_surface", "transport_unavailable"].contains(reason)
    }
    public func capture(_ anchor: ReplyCaptureAnchor, snapshotId: String, bundle: String, pid: Int32?) async throws -> ReplyCaptureResult {
        var fallback: String?
        if anchor.selectedSource == nil && bundle == "com.google.Chrome", let pid,
           ProcessInfo.processInfo.environment["KEIGO_REPLY_DOM"] != "0" {
            do {
                let response = try await browser.capture(snapshotId: snapshotId, browserPID: pid)
                try Task.checkCancellation()
                return ReplyCaptureResult(evidence: response.evidence!, binding: response.binding, source: "dom", fallbackReason: nil, failureReason: nil, observations: [])
            } catch is CancellationError { throw CancellationError() }
            catch {
                let reason = (error as? BrowserReplyError)?.reason ?? "transport_unavailable"
                if Self.permitsAXFallback(reason) { fallback = reason }
                else {
                    return ReplyCaptureResult(evidence: CapturedReplyEvidence(snapshotId: snapshotId, blocks: [], status: .unavailable, truncationReasons: [reason]), binding: nil, source: "dom", fallbackReason: nil, failureReason: reason, observations: [])
                }
            }
        }
        let evidence = try await ax.read(anchor, snapshotId: snapshotId)
        return ReplyCaptureResult(evidence: evidence, binding: nil, source: anchor.selectedSource == nil ? "ax" : "selection", fallbackReason: fallback, failureReason: nil, observations: await ax.observations)
    }
}
