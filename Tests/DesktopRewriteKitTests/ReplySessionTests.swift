import XCTest
@testable import DesktopRewriteKit

final class ReplySessionTests: XCTestCase {
    private let block = ReplySourceBlock(id: "b0", conversationId: "c0", text: "明日？", order: 0)
    private func ready(_ id: String = "session") -> (ReplySession, ReplyContextOutcome) {
        var session = ReplySession(id: id, draftStatus: .empty)
        session.captured(CapturedReplyEvidence(snapshotId: id, blocks: [block], status: .partial, truncationReasons: ["visible_history_only"]))
        var selected = session
        selected.choose(blocks: [block], audience: .direct)
        return (session, ReplyContextOutcome(snapshotId: id, status: "ready", context: selected.context, candidateIds: ["b0"], reason: "selected"))
    }
    func testQueuedSendRunsOnceWithOriginalGuidance() {
        var (session, outcome) = ready()
        session.queue("decline")
        session.queue("accept")
        XCTAssertEqual(session.accept(outcome), "decline")
        XCTAssertNil(session.accept(outcome))
        XCTAssertEqual(session.phase, .ready)
    }
    func testStaleSessionCannotReplaceSourceOrConsumeSend() {
        var (session, _) = ready()
        let (_, stale) = ready("old")
        session.queue("Friday")
        XCTAssertNil(session.accept(stale))
        XCTAssertNil(session.context)
        XCTAssertEqual(session.queuedGuidance, "Friday")
    }
    func testFailureUnlocksEditingAndRequiresFreshSubmission() {
        var (session, _) = ready()
        session.queue("")
        session.fail()
        XCTAssertNil(session.queuedGuidance)
        XCTAssertEqual(session.phase, .needsSource)
    }
    func testProviderCannotReplaceCapturedText() {
        var (session, _) = ready()
        var forged = ReplySession(id: "session", draftStatus: .empty)
        forged.choose(blocks: [ReplySourceBlock(id: "b0", conversationId: "c0", text: "I accept", order: 0)], audience: .direct)
        XCTAssertNil(session.accept(ReplyContextOutcome(snapshotId: "session", status: "ready", context: forged.context, candidateIds: ["b0"], reason: "selected")))
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertNil(session.context)
    }
    func testExplicitShortSourceAndUnknownDraftSurviveSerialization() throws {
        var session = ReplySession(id: "s", draftStatus: .unreadable)
        session.choose(blocks: [block], audience: .group)
        let request = RewriteRequest(prompt: "", text: "", appVersion: "test", captureMode: .wholeInput,
                                     replyContext: session.context, draftReadStatus: session.draftStatus)
        let decoded = try JSONDecoder().decode(RewriteRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.replyContext?.selectedTargetText, "明日？")
        XCTAssertEqual(decoded.draftReadStatus, .unreadable)
        XCTAssertNil(decoded.replyTo)
        XCTAssertEqual(decoded.replyContext?.audience.kind, .group)
    }
    func testFrozenContextIsIndependentOfLaterSourceSelection() {
        var session = ReplySession(id: "s", draftStatus: .present)
        session.choose(blocks: [block], audience: .direct)
        let frozen = session.context
        session.choose(blocks: [ReplySourceBlock(id: "other", conversationId: "other", text: "Different thread", order: 0)], audience: .group)
        XCTAssertEqual(frozen?.selectedTargetText, "明日？")
        XCTAssertEqual(frozen?.audience.kind, .direct)
    }
    func testSourceChoiceCannotMergeDifferentThreads() {
        var session = ReplySession(id: "s", draftStatus: .empty)
        session.choose(blocks: [block, ReplySourceBlock(id: "b1", conversationId: "c1", text: "other", order: 1)], audience: .group)
        XCTAssertNil(session.context)
    }
}

extension ReplySessionTests {
    func testResourceFailureKeepsEvidenceWithoutPretendingUserMustChoose() {
        var (session, _) = ready()
        session.queue("decline")
        _ = session.accept(ReplyContextOutcome(snapshotId: "session", status: "unavailable", context: nil, candidateIds: [], reason: "analysis_budget"))
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertEqual(session.failureReason, "analysis_budget")
        XCTAssertNotNil(session.evidence)
        XCTAssertNil(session.queuedGuidance)
        XCTAssertFalse(session.canRetryAnalysis)
    }
    func testScopedRetryRetainsSnapshotAndDoesNotAcceptAnotherPane() {
        var session = ReplySession(id: "s", draftStatus: .empty)
        let source = ReplySourceBlock(id: "b", conversationId: "history", text: "message", order: 0)
        let other = ReplySourceBlock(id: "other", conversationId: "other", text: "other", order: 1)
        session.captured(CapturedReplyEvidence(version: 2, snapshotId: "s", blocks: [source, other], status: .partial, truncationReasons: [], regions: [
            ReplyCaptureRegion(id: "pane", role: "AXGroup", containsFocus: true),
            ReplyCaptureRegion(id: "history", parentId: "pane", role: "AXScrollArea", containsFocus: false),
            ReplyCaptureRegion(id: "other", role: "AXGroup", containsFocus: false)
        ]))
        session.scope(to: "pane")
        XCTAssertEqual(session.analysisEvidence?.blocks, [source])
        XCTAssertEqual(session.evidence?.blocks.count, 2)
        XCTAssertEqual(session.analysisEvidence?.snapshotId, "s")
        var wrong = ReplySession(id: "s", draftStatus: .empty)
        wrong.choose(blocks: [other], audience: .direct)
        _ = session.accept(ReplyContextOutcome(snapshotId: "s", status: "ready", context: wrong.context, candidateIds: [], reason: "selected"))
        XCTAssertEqual(session.phase, .unavailable)
    }
}

extension ReplySessionTests {
    func testCandidateScopeUsesExactIDsAndRetainsSupportWithoutBroadeningWrapper() {
        var session = ReplySession(id: "s", draftStatus: .empty)
        let source = ReplySourceBlock(id: "b1", conversationId: "history", text: "message", order: 1)
        let header = ReplySourceBlock(id: "b0", conversationId: "root", text: "To: Alex", order: 0)
        let other = ReplySourceBlock(id: "b2", conversationId: "other", text: "unrelated", order: 2)
        session.captured(CapturedReplyEvidence(version: 3, snapshotId: "s", blocks: [header, source, other], status: .partial, truncationReasons: [], regions: [
            ReplyCaptureRegion(id: "root", role: "AXGroup", containsFocus: true),
            ReplyCaptureRegion(id: "history", parentId: "root", role: "AXScrollArea", containsFocus: false),
            ReplyCaptureRegion(id: "other", parentId: "root", role: "AXList", containsFocus: false)
        ]))
        var outcome = ReplyContextOutcome(snapshotId: "s", status: "needs_choice", context: nil, candidateIds: [], reason: "ambiguous_conversation")
        outcome.candidates = [ReplyCandidate(id: "root", regionIds: ["root", "history"], sourceBlockIds: ["b1"], supportBlockIds: ["b0"], containsFocus: true)]
        outcome.candidateRegionIds = ["root"]
        _ = session.accept(outcome)
        let attempt = session.attemptId
        session.scope(to: "root")
        XCTAssertEqual(session.analysisEvidence?.blocks, [header, source])
        XCTAssertFalse(session.analysisEvidence?.regions?.contains { $0.id == "other" } == true)
        XCTAssertEqual(session.evidence?.blocks.count, 3)
        XCTAssertNotEqual(session.attemptId, attempt)
        XCTAssertEqual(session.analysisEvidence?.snapshotId, "s")
    }
}

extension ReplySessionTests {
    func testCaptureGapRetainsGuidanceFlowButCannotRetryMissingSnapshot() {
        var (session, _) = ready()
        session.queue("decline")
        _ = session.accept(ReplyContextOutcome(snapshotId: "session", status: "unavailable", context: nil, candidateIds: [], reason: "capture_incomplete"))
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertFalse(session.canRetryAnalysis)
        XCTAssertNotNil(session.evidence)
        XCTAssertNil(session.queuedGuidance)
    }
    func testOldInterpretationDiagnosticsDecodeWithoutNewAudienceFields() throws {
        let data = Data("""
        {"revision":"capture-v3-candidates-1","providerCalls":2,"requestBytes":[],"questionCounts":[],"optionCounts":[],"candidatesBefore":1,"candidatesDistinct":1,"candidatesOmitted":0,"selectedSources":1,"selectedSupport":0,"stage":"detail"}
        """.utf8)
        let diagnostics = try JSONDecoder().decode(ReplyInterpretationDiagnostics.self, from: data)
        XCTAssertNil(diagnostics.audienceRawChoice)
        XCTAssertNil(diagnostics.audienceForcedAbstention)
        XCTAssertNil(diagnostics.selectedRegionId)
    }
    func testScopedPaneRetainsTextFreeComposerSibling() {
        var session = ReplySession(id: "s", draftStatus: .empty)
        session.captured(CapturedReplyEvidence(version: 3, snapshotId: "s", blocks: [
            ReplySourceBlock(id: "message", conversationId: "history", text: "Hello", order: 0)
        ], status: .partial, truncationReasons: [], regions: [
            ReplyCaptureRegion(id: "pane", role: "AXGroup", containsFocus: true),
            ReplyCaptureRegion(id: "history", parentId: "pane", role: "AXScrollArea", containsFocus: false),
            ReplyCaptureRegion(id: "field", parentId: "pane", role: "AXGroup", containsFocus: true)
        ], observations: [ReplyCaptureObservation(regionId: "field", role: "AXTextArea", kind: "composer", containsFocus: true)]))
        session.scope(to: "pane")
        XCTAssertTrue(session.analysisEvidence?.regions?.contains { $0.id == "field" } == true)
        XCTAssertEqual(session.analysisEvidence?.observations?.first?.regionId, "field")
    }
}

extension ReplySessionTests {
    func testMissingCurrentHistoryRequiresFreshCapture() {
        var session = ReplySession(id: "s", draftStatus: .empty)
        session.captured(CapturedReplyEvidence(snapshotId: "s", blocks: [], status: .unavailable, truncationReasons: ["missing_current_history"]))
        _ = session.accept(ReplyContextOutcome(snapshotId: "s", status: "unavailable", context: nil, candidateIds: [], reason: "missing_current_history"))
        XCTAssertFalse(session.canRetryAnalysis)
        XCTAssertEqual(session.phase, .unavailable)
    }
    func testTurnDiagnosticsRetainCandidateAnchorContextAndRejectingHead() throws {
        let data = Data("""
        {"revision":"capture-v3-turns-1","providerCalls":2,"requestBytes":[],"questionCounts":[],"optionCounts":[],"candidatesBefore":1,"candidatesDistinct":1,"candidatesOmitted":0,"selectedSources":3,"selectedSupport":0,"stage":"detail","messageCandidates":[{"id":"t0","sourceBlockIds":["b0","b1"],"boundary":"history_item","visibility":"visible"}],"anchorMessageId":"t0","contextMessageIds":["t1"],"rejectionDecision":"anchor","decisions":{"anchor":{"raw":"t0","effective":"uncertain","margin":0.08,"forced":true}}}
        """.utf8)
        let diagnostics = try JSONDecoder().decode(ReplyInterpretationDiagnostics.self, from: data)
        let roundTrip = try JSONDecoder().decode(ReplyInterpretationDiagnostics.self, from: JSONEncoder().encode(diagnostics))
        XCTAssertEqual(diagnostics, roundTrip)
        XCTAssertEqual(roundTrip.messageCandidates?.first?.sourceBlockIds, ["b0", "b1"])
        XCTAssertEqual(roundTrip.anchorMessageId, "t0")
        XCTAssertEqual(roundTrip.contextMessageIds, ["t1"])
        XCTAssertEqual(roundTrip.rejectionDecision, "anchor")
        XCTAssertEqual(roundTrip.decisions?["anchor"]?.forced, true)
    }
}
