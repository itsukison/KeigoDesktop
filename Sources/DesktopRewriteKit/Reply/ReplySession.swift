import Foundation

public enum ReplyContextFeature {
    // Continue automatic context capture on codex/reply-context-experiment.
    public static let isEnabled = false
}

public enum ReplyAnalysisError: String, Error, Sendable {
    case unauthorized, context_rate_limited, context_timeout, context_unavailable
    case provider_not_configured, provider_rate_limited, provider_unavailable, invalid_provider_response
    case invalid_reply_context, payload_too_large, rate_limit_unavailable
}

public struct ReplyCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let regionIds: [String]
    public let sourceBlockIds: [String]
    public let supportBlockIds: [String]
    public let containsFocus: Bool
}

public struct ReplyTurnDiagnostic: Codable, Equatable, Sendable {
    public let id: String
    public let sourceBlockIds: [String]
    public let boundary: String
    public let visibility: String
}
public struct ReplyDecisionDiagnostic: Codable, Equatable, Sendable {
    public let raw: String
    public let effective: String
    public let margin: Double
    public let forced: Bool
}
public struct ReplyInterpretationDiagnostics: Codable, Equatable, Sendable {
    public let messageCandidates: [ReplyTurnDiagnostic]?
    public let anchorMessageId: String?
    public let contextMessageIds: [String]?
    public let rejectionDecision: String?
    public let decisions: [String: ReplyDecisionDiagnostic]?
    public let revision: String
    public let providerCalls: Int
    public let requestBytes: [Int]
    public let questionCounts: [Int]
    public let optionCounts: [Int]
    public let candidatesBefore: Int
    public let candidatesDistinct: Int
    public let candidatesOmitted: Int
    public let selectedSources: Int
    public let selectedSupport: Int
    public let stage: String
    public let validationFailure: String?
    public let routeMargin: Double?
    public let selectedRegionId: String?
    public let audienceRawChoice: String?
    public let audienceEffectiveChoice: String?
    public let audienceMargin: Double?
    public let audienceForcedAbstention: Bool?
}

public struct ReplyAnalysisFailure: Error, Sendable {
    public let code: ReplyAnalysisError
    public let diagnostics: ReplyInterpretationDiagnostics?
    public init(code: ReplyAnalysisError, diagnostics: ReplyInterpretationDiagnostics?) {
        self.code = code; self.diagnostics = diagnostics
    }
}

public struct ReplyContextOutcome: Codable, Sendable {
    public let snapshotId: String
    public let status: String
    public let context: ReplyContext?
    public let candidateIds: [String]
    public let reason: String
    public var candidateRegionIds: [String]? = nil
    public var candidates: [ReplyCandidate]? = nil
    public var diagnostics: ReplyInterpretationDiagnostics? = nil
}

public struct ReplySession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case loading, ready, needsSource, unavailable }
    public let id: String
    public let draftStatus: ReplyDraftReadStatus
    public private(set) var phase: Phase = .loading
    public private(set) var evidence: CapturedReplyEvidence?
    public private(set) var context: ReplyContext?
    public private(set) var queuedGuidance: String?
    public private(set) var failureReason: String?
    public private(set) var suggestedRegionIDs: [String] = []
    public private(set) var candidates: [ReplyCandidate] = []
    public private(set) var diagnostics: ReplyInterpretationDiagnostics?
    public private(set) var attemptId = UUID().uuidString
    public private(set) var analysisEvidence: CapturedReplyEvidence?

    public init(id: String = UUID().uuidString, draftStatus: ReplyDraftReadStatus) {
        self.id = id
        self.draftStatus = draftStatus
    }
    public mutating func captured(_ evidence: CapturedReplyEvidence) {
        guard evidence.snapshotId == id else { return }
        self.evidence = evidence
        self.analysisEvidence = evidence
    }
    public mutating func accept(_ outcome: ReplyContextOutcome) -> String? {
        guard outcome.snapshotId == id else { return nil }
        diagnostics = outcome.diagnostics
        if let evidence = analysisEvidence {
            let blockIDs = Set(evidence.blocks.map(\.id))
            let regionIDs = Set(evidence.regions?.map(\.id) ?? evidence.blocks.map(\.conversationId))
            candidates = Array((outcome.candidates ?? []).filter { candidate in
                let sources = Set(candidate.sourceBlockIds), support = Set(candidate.supportBlockIds)
                return regionIDs.contains(candidate.id) && !sources.isEmpty
                    && sources.count == candidate.sourceBlockIds.count && support.count == candidate.supportBlockIds.count
                    && sources.isDisjoint(with: support) && sources.union(support).isSubset(of: blockIDs)
                    && Set(candidate.regionIds).isSubset(of: regionIDs)
            }.prefix(8))
        }
        suggestedRegionIDs = Array((outcome.candidateRegionIds ?? []).prefix(4)).filter { !blocks(in: $0).isEmpty }
        guard outcome.status == "ready" else {
            fail(unavailable: outcome.status != "needs_choice", reason: outcome.reason)
            return nil
        }
        guard let context = outcome.context, context.snapshotId == id,
              let evidence = analysisEvidence, context.isBound(to: evidence) else {
            fail(unavailable: true, reason: "invalid_provider_response"); return nil
        }
        self.context = context
        failureReason = nil
        phase = .ready
        let guidance = queuedGuidance
        queuedGuidance = nil
        return guidance
    }
    public mutating func queue(_ guidance: String) {
        guard phase == .loading, queuedGuidance == nil else { return }
        queuedGuidance = guidance
    }
    public mutating func retry() { attemptId = UUID().uuidString; diagnostics = nil; phase = .loading; queuedGuidance = nil; context = nil; failureReason = nil }
    public mutating func fail(unavailable: Bool = false, reason: String? = nil) {
        phase = unavailable ? .unavailable : .needsSource
        failureReason = reason; queuedGuidance = nil; context = nil
    }
    public mutating func fail(_ error: Error) {
        let reason: String
        if let failure = error as? ReplyAnalysisFailure {
            diagnostics = failure.diagnostics; reason = failure.code.rawValue
        }
        else if let analysis = error as? ReplyAnalysisError { reason = analysis.rawValue }
        else if error as? RewriteError == .notSignedIn { reason = "unauthorized" }
        else if (error as? URLError)?.code == .timedOut { reason = "context_timeout" }
        else { reason = "context_unavailable" }
        fail(unavailable: true, reason: reason)
    }
    public var canRetryAnalysis: Bool {
        guard analysisEvidence?.blocks.isEmpty == false else { return false }
        return !["capture_incomplete", "missing_current_history", "analysis_budget", "capture_budget", "candidate_coverage", "invalid_reply_context", "payload_too_large", "unauthorized", "provider_not_configured"].contains(failureReason ?? "")
    }
    public func blocks(in regionID: String) -> [ReplySourceBlock] {
        guard let evidence else { return [] }
        if let candidate = candidates.first(where: { $0.id == regionID }) {
            let ids = Set(candidate.sourceBlockIds + candidate.supportBlockIds)
            return evidence.blocks.filter { ids.contains($0.id) }
        }
        var ids: Set<String> = [regionID]
        for _ in evidence.regions ?? [] {
            for region in evidence.regions ?? [] where region.parentId.map(ids.contains) == true { ids.insert(region.id) }
        }
        return evidence.blocks.filter { ids.contains($0.conversationId) }
    }
    public mutating func scope(to regionID: String) {
        guard let evidence else { return }
        let selected = blocks(in: regionID)
        guard !selected.isEmpty else { return }
        var localRegions: Set<String> = [regionID]
        for _ in evidence.regions ?? [] {
            for region in evidence.regions ?? [] where region.parentId.map(localRegions.contains) == true { localRegions.insert(region.id) }
        }
        var regionIDs = Set(selected.map(\.conversationId))
        // Keep text-free field wrappers inside the selected pane. Equivalent broad
        // ancestors supply relationships, not unrelated descendants' observations.
        for observation in evidence.observations ?? [] where observation.blockId == nil && localRegions.contains(observation.regionId) {
            regionIDs.insert(observation.regionId)
        }
        regionIDs.insert(regionID)
        for _ in evidence.regions ?? [] {
            for region in evidence.regions ?? [] where regionIDs.contains(region.id) {
                if let parent = region.parentId { regionIDs.insert(parent) }
            }
        }
        analysisEvidence = CapturedReplyEvidence(version: evidence.version, snapshotId: id, blocks: selected,
            status: .partial, truncationReasons: evidence.truncationReasons, regions: evidence.regions?.filter { regionIDs.contains($0.id) },
            observations: evidence.observations?.filter { observation in
                observation.blockId.map { id in selected.contains { $0.id == id } } ?? localRegions.contains(observation.regionId)
            }, diagnostics: evidence.diagnostics, dom: evidence.dom?.scoped(to: regionID))
        retry()
    }
    public mutating func choose(blocks: [ReplySourceBlock], audience: ReplyAudienceKind) {
        guard !blocks.isEmpty, audience != .unknown, blocks.allSatisfy({ $0.conversationId == blocks[0].conversationId }),
              blocks.reduce(0, { $0 + $1.text.utf16.count }) <= 12000 else { return }
        // Manual selection supplies intent and audience, not inferred speaker identities.
        context = ReplyContext(snapshotId: id, conversationId: blocks[0].conversationId,
            sourceBlocks: blocks.map { ReplySourceBlock(id: $0.id, conversationId: $0.conversationId, text: $0.text, order: $0.order, role: $0.role) }, participants: [],
            messages: blocks.map { ReplyMessage(id: "m_\($0.id)", text: $0.text, sourceBlockIds: [$0.id], order: $0.order, kind: .message) },
            targetMessageIds: blocks.map { "m_\($0.id)" }, audience: ReplyAudience(kind: audience, participantIds: []),
            completeness: .partial, uncertainties: [ReplyUncertainty(kind: .speaker, material: false, sourceBlockIds: blocks.map(\.id))])
        phase = .ready
        queuedGuidance = nil
    }
}

extension ReplyContext {
    public func isBound(to evidence: CapturedReplyEvidence) -> Bool {
        guard snapshotId == evidence.snapshotId, !targetMessageIds.isEmpty,
              Set(sourceBlocks.map(\.id)).count == sourceBlocks.count,
              sourceBlocks.allSatisfy({ evidence.blocks.contains($0) }),
              messages.allSatisfy({ message in
                  let sources = message.sourceBlockIds.compactMap { id in sourceBlocks.first { $0.id == id } }
                  return !sources.isEmpty && sources.count == message.sourceBlockIds.count
                    && message.text == sources.map(\.text).joined(separator: "\n")
              }), targetMessageIds.allSatisfy({ id in messages.contains { $0.id == id } }),
              audience.kind != .unknown, !uncertainties.contains(where: \.material) else { return false }
        return true
    }
}
