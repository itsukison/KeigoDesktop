import XCTest
@testable import TextIO

final class ConversationTraversalTests: XCTestCase {
    final class Tree: ConversationTreeAccess {
        var samples: [Int: ConversationNodeSample] = [:]
        var edges: [Int: [Int]] = [:]
        var reads: [Int] = []
        var metadataReads: [Int] = []
        func metadata(_ node: Int) -> ConversationNodeSample? { metadataReads.append(node); return samples[node] }
        func composer(_ node: Int) -> ConversationNodeSample? { samples[node] ?? ConversationNodeSample(role: "AXTextArea", text: nil, frame: nil) }
        var requestedLimits: [Int] = []
        var repeatFirstPage = false
        func sample(_ node: Int) -> ConversationNodeSample? { reads.append(node); return samples[node] }
        func children(_ node: Int, offset: Int, limit: Int) -> (nodes: [Int], truncated: Bool, errorCode: Int?) {
            requestedLimits.append(limit)
            let all = edges[node] ?? []
            return (Array(all.dropFirst(repeatFirstPage ? 0 : offset).prefix(limit)), all.count > offset + limit, nil)
        }
    }
    private func text(_ value: String, frame: CGRect? = nil) -> ConversationNodeSample {
        ConversationNodeSample(role: "AXStaticText", text: value, frame: frame)
    }
    func testCyclesAreBoundedAndIdenticalMessagesKeepDistinctIdentity() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil), 1: text("同じ"), 2: text("同じ")]
        tree.edges = [0: [1, 2], 1: [0, 2]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.map(\.text), ["同じ", "同じ"])
        XCTAssertEqual(Set(evidence.blocks.map(\.id)).count, 2)
        XCTAssertEqual(tree.metadataReads.count, 3)
        XCTAssertEqual(tree.reads.count, 2)
    }
    func testClippingExcludesOffscreenButPreservesUnknownGeometry() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXScrollArea", text: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
                        1: text("visible", frame: CGRect(x: 10, y: 10, width: 40, height: 20)),
                        2: text("offscreen", frame: CGRect(x: 10, y: 150, width: 40, height: 20)), 3: text("unknown")]
        tree.edges = [0: [1, 2, 3]]
        let (evidence, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.map(\.text), ["visible", "unknown"])
        XCTAssertTrue(evidence.truncationReasons.contains("unknown_geometry"))
        XCTAssertTrue(observations.contains { $0.clipped })
    }
    func testDraftAndSecureSubtreesAreNeverCaptured() throws {
        let tree = Tree()
        tree.samples = [0: text("source"), 1: text("draft"), 2: ConversationNodeSample(role: "AXSecureTextField", text: "secret", frame: nil), 3: text("secret child")]
        tree.edges = [0: [1, 2], 2: [3]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 1, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.map(\.text), ["source"])
        XCTAssertFalse(tree.reads.contains(1)); XCTAssertFalse(tree.reads.contains(3))
    }
    func testChildNodeAndTextBudgetsPreservePartialStatus() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil), 1: text("a"), 2: text("too long"), 3: text("other")]
        tree.edges = [0: [1, 2, 3]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(nodes: 3, children: 2, blocks: 5, textUnits: 2, seconds: 1))
        XCTAssertEqual(evidence.blocks.map(\.text), ["a"])
        XCTAssertTrue(evidence.truncationReasons.contains("child_budget"))
        XCTAssertTrue(evidence.truncationReasons.contains("text_budget"))
        XCTAssertEqual(evidence.status.rawValue, "partial")
        XCTAssertTrue(tree.requestedLimits.allSatisfy { $0 <= 2 })
    }
    func testDeadlineAndCancellationStopBeforeFurtherIPC() throws {
        let tree = Tree(); tree.samples = [0: text("source")]; tree.edges = [0: [1]]
        var tick = 0
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", now: { defer { tick += 1 }; return Date(timeIntervalSince1970: Double(tick)) })
        XCTAssertTrue(tree.reads.isEmpty)
        XCTAssertTrue(evidence.truncationReasons.contains("time_budget"))
        XCTAssertThrowsError(try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", cancelled: { true }))
    }
    func testPartialAttributeFailureDoesNotEraseReadableText() throws {
        let tree = Tree(); tree.samples = [0: ConversationNodeSample(role: "AXStaticText", text: "message", frame: nil, sourceAttribute: "AXValue", failedAttributes: ["AXPosition"])]
        let (evidence, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.first?.text, "message")
        XCTAssertEqual(observations.first?.failedAttributes, ["AXPosition"])
        XCTAssertTrue(evidence.truncationReasons.contains("partial_attributes"))
    }
}

extension ConversationTraversalTests {
    func testReadonlyMessageAreaIsSourceButUnknownEditableAreaIsNot() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil),
                        1: ConversationNodeSample(role: "AXTextArea", text: "received email", frame: nil, isEditable: false),
                        2: ConversationNodeSample(role: "AXTextArea", text: "unknown field contents", frame: nil)]
        tree.edges = [0: [1, 2]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.map(\.text), ["received email"])
    }
}

extension ConversationTraversalTests {
    func testFocusedPaneIsCapturedBeforeSidebarConsumesBudgetAndCarriesAncestry() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil),
                        1: ConversationNodeSample(role: "AXScrollArea", text: nil, frame: nil),
                        2: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil),
                        3: text("sidebar"), 4: text("incoming"), 5: text("private draft")]
        tree.edges = [0: [1, 2], 1: [3], 2: [4, 5]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 5, snapshotId: "s", focusPath: [0, 2, 5], limits: .init(blocks: 1))
        XCTAssertEqual(evidence.version, 3)
        XCTAssertEqual(evidence.blocks.map(\.text), ["incoming"])
        let region = try XCTUnwrap(evidence.regions?.first { $0.id == evidence.blocks[0].conversationId })
        XCTAssertTrue(region.containsFocus)
        XCTAssertEqual(region.parentId, "c0")
        XCTAssertFalse(tree.reads.contains(5))
    }
    func testNestedRegionsRetainParentRelationshipAndDuplicateSourceIdentity() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil),
                        1: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil),
                        2: text("header"), 3: ConversationNodeSample(role: "AXScrollArea", text: nil, frame: nil),
                        4: text("same"), 5: text("same")]
        tree.edges = [0: [1], 1: [2, 3], 3: [4, 5]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        let header = evidence.blocks[0]; let message = evidence.blocks[1]
        XCTAssertEqual(evidence.regions?.first { $0.id == message.conversationId }?.parentId, header.conversationId)
        XCTAssertEqual(evidence.blocks.map(\.text), ["header", "same", "same"])
        XCTAssertEqual(Set(evidence.blocks.map(\.id)).count, 3)
    }
    func testOversizedUnrelatedNodeDoesNotPreventReadingLaterSource() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil), 1: text("too long"), 2: text("ok")]
        tree.edges = [0: [1, 2]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(textUnits: 2))
        XCTAssertEqual(evidence.blocks.map(\.text), ["ok"])
        XCTAssertTrue(evidence.truncationReasons.contains("text_budget"))
    }
}

extension ConversationTraversalTests {
    func testDeepFocusPathDoesNotReserveSampleBudgetForPendingSiblings() throws {
        let tree = Tree()
        for id in 0...450 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil) }
        tree.samples[999] = text("incoming deep message")
        tree.edges = [0: Array(1...200), 1: Array(201...400), 201: Array(401...450), 401: [999]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s",
            focusPath: [0, 1, 201, 401], limits: .init(nodes: 451))
        XCTAssertEqual(evidence.blocks.first?.text, "incoming deep message")
        XCTAssertLessThan(tree.reads.firstIndex(of: 999) ?? 500, 10)
        XCTAssertEqual(evidence.diagnostics?.focusPathRead, 4)
    }
    func testFocusChildBeyondFirstTwoHundredIsVisitedDirectly() throws {
        let tree = Tree()
        for id in 0...200 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil) }
        tree.samples[999] = text("late active message")
        tree.edges[0] = Array(1...200) + [999]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", focusPath: [0, 999])
        XCTAssertEqual(tree.metadataReads.prefix(2), [0, 999])
        XCTAssertEqual(evidence.blocks.first?.text, "late active message")
    }
    func testChildPagesAreResumedAndPartialForeignFocusDoesNotReadAnotherWindow() throws {
        let tree = Tree()
        tree.samples[0] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil)
        for id in 1...5 { tree.samples[id] = text("message \(id)") }
        tree.samples[999] = text("foreign window")
        tree.edges[0] = Array(1...5)
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", focusPath: [998, 999], limits: .init(children: 2))
        XCTAssertEqual(evidence.blocks.count, 5)
        XCTAssertFalse(tree.reads.contains(999))
        XCTAssertEqual(evidence.diagnostics?.focusReachesRoot, false)
        XCTAssertFalse(evidence.truncationReasons.contains("child_budget"))
    }
    func testControlLabelSupportsContextAndEditableValueIsExcluded() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil),
            1: ConversationNodeSample(role: "AXButton", text: "To: Alex", frame: nil, sourceAttribute: "AXTitle"),
            2: text("incoming"), 3: ConversationNodeSample(role: "AXTextArea", text: "private draft", frame: nil, isEditable: true)]
        tree.edges = [0: [1, 2, 3], 3: [4]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.map(\.text), ["To: Alex", "incoming"])
        XCTAssertTrue(evidence.observations?.contains { $0.kind == "control_label" && $0.sourceAttribute == "AXTitle" } == true)
        XCTAssertTrue(evidence.observations?.contains { $0.kind == "composer" && $0.blockId == nil } == true)
        XCTAssertFalse(tree.reads.contains(4))
    }
    func testNoFocusedComposerStillAllocatesWorkToSecondPane() throws {
        let tree = Tree()
        for id in 0...300 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil) }
        tree.edges[0] = [1, 300]
        for id in 1..<299 { tree.edges[id] = [id + 1] }
        tree.samples[300] = text("visible alternative")
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(nodes: 100))
        XCTAssertEqual(evidence.blocks.first?.text, "visible alternative")
        XCTAssertTrue(evidence.truncationReasons.contains("node_budget"))
    }
}

extension ConversationTraversalTests {
    func testRepeatedPagesTerminateWithDistinctDiagnostic() throws {
        let tree = Tree(); tree.repeatFirstPage = true
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil), 1: text("one"), 2: text("two"), 3: text("three")]
        tree.edges[0] = [1, 2, 3]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(children: 2))
        XCTAssertEqual(evidence.blocks.map(\.text), ["one", "two"])
        XCTAssertTrue(evidence.truncationReasons.contains("repeated_child_page"))
        XCTAssertLessThan(evidence.diagnostics?.childPages ?? 99, 10)
    }
    func testBlockExhaustionIsNotMislabeledAsNodeExhaustion() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil), 1: text("one"), 2: text("two")]
        tree.edges[0] = [1, 2]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(blocks: 1))
        XCTAssertTrue(evidence.truncationReasons.contains("block_budget"))
        XCTAssertFalse(evidence.truncationReasons.contains("node_budget"))
    }
}

extension ConversationTraversalTests {
    func testLongFocusSpineAndNearbySiblingsWinBeforeSidebar() throws {
        let tree = Tree()
        for id in 0...160 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil) }
        tree.samples[0] = ConversationNodeSample(role: "AXWindow", text: nil, frame: nil)
        tree.edges[0] = [100, 1]
        for id in 1..<40 { tree.edges[id] = [id + 1] }
        tree.edges[40] = [41, 42, 43]
        tree.samples[41] = ConversationNodeSample(role: "AXHeading", text: "Alex", frame: nil)
        tree.samples[42] = text("Main incoming message")
        tree.samples[43] = ConversationNodeSample(role: "AXTextArea", text: "private draft", frame: nil)
        tree.edges[100] = Array(101...160)
        for id in 101...160 { tree.samples[id] = text("Sidebar \(id)") }
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 43, snapshotId: "s", focusPath: Array(0...40) + [43], limits: .init(blocks: 2))
        XCTAssertEqual(evidence.blocks.map(\.text), ["Alex", "Main incoming message"])
        XCTAssertTrue(evidence.observations?.contains { $0.kind == "composer" && $0.containsFocus } == true)
        XCTAssertFalse(tree.reads.contains(43))
    }

    func testPartialAncestryReconnectsOnlyAfterTopIsReachedFromWindow() throws {
        let tree = Tree()
        for id in 0...5 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil) }
        tree.edges = [0: [1], 1: [2], 2: [3, 4], 4: [5, 6]]
        tree.samples[3] = text("sidebar")
        tree.samples[5] = text("incoming")
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 6, snapshotId: "s", focusPath: [2, 4, 6], limits: .init(blocks: 1))
        XCTAssertEqual(evidence.blocks.map(\.text), ["incoming"])
        XCTAssertTrue(evidence.observations?.contains { $0.containsFocus && $0.kind == "composer" } == true)
    }

    func testFullTextBufferStillVisitsFieldMetadata() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil), 1: text("message"), 2: text("another")]
        tree.edges = [0: [1, 2, 3]]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 3, snapshotId: "s", limits: .init(blocks: 1))
        XCTAssertEqual(evidence.blocks.count, 1)
        XCTAssertEqual(evidence.observations?.filter { $0.kind == "composer" }.count, 1)
    }

    func testNeutralWrappersCompactWithoutMergingSiblingSources() throws {
        let tree = Tree()
        for id in 0...150 { tree.samples[id] = ConversationNodeSample(role: "AXGroup", text: nil, frame: nil); tree.edges[id] = [id + 1] }
        tree.edges[150] = [151, 152]
        tree.samples[151] = ConversationNodeSample(role: "AXScrollArea", text: nil, frame: nil)
        tree.samples[152] = ConversationNodeSample(role: "AXScrollArea", text: nil, frame: nil)
        tree.edges[151] = [153]; tree.edges[152] = [154]
        tree.samples[153] = text("same"); tree.samples[154] = text("same")
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.blocks.count, 2)
        XCTAssertNotEqual(evidence.blocks[0].conversationId, evidence.blocks[1].conversationId)
        XCTAssertLessThan(evidence.regions?.count ?? 999, 10)
        XCTAssertFalse(evidence.truncationReasons.contains("region_budget"))
    }

    func testSearchAndUnknownSingleLineFieldsAreStructureNotComposer() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil),
            1: ConversationNodeSample(role: "AXSearchField", text: "private query", frame: nil),
            2: ConversationNodeSample(role: "AXTextField", text: "private draft", frame: nil),
            3: ConversationNodeSample(role: "AXTextArea", text: "private draft", frame: nil)]
        tree.edges[0] = [1, 2, 3]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertTrue(evidence.blocks.isEmpty)
        XCTAssertEqual(evidence.observations?.filter { $0.kind == "composer" }.map(\.role), ["AXTextArea"])
        XCTAssertEqual(evidence.observations?.filter { $0.kind == "structure" }.count, 2)
    }
}

extension ConversationTraversalTests {
    func testAncestryReachesRootBeyondOldDepthLimit() throws {
        let result = try ConversationAncestry.read(focused: 40, root: 0) { $0 > 0 ? $0 - 1 : nil }
        XCTAssertEqual(result.path, Array(0...40))
        XCTAssertEqual(result.termination, "root")
        let limited = try ConversationAncestry.read(focused: 100, root: 0) { $0 - 1 }
        XCTAssertEqual(limited.path.count, 64)
        XCTAssertEqual(limited.termination, "depth_budget")
    }
    func testAncestryCycleDeadlineMissingParentAndCancellation() throws {
        let cycle = try ConversationAncestry.read(focused: 2, root: 0) { $0 == 2 ? 1 : 2 }
        XCTAssertEqual(cycle.termination, "cycle")
        let missing = try ConversationAncestry.read(focused: 2, root: 0) { _ in nil }
        XCTAssertEqual(missing.termination, "parent_unavailable")
        var tick = 0
        let expired = try ConversationAncestry.read(focused: 2, root: 0, now: {
            defer { tick += 1 }; return Date(timeIntervalSince1970: Double(tick))
        }) { _ in XCTFail("No IPC after deadline"); return nil }
        XCTAssertEqual(expired.termination, "time_budget")
        XCTAssertThrowsError(try ConversationAncestry.read(focused: 2, root: 0, cancelled: { true }) { _ in nil })
    }
    func testFullBufferUsesMetadataReadsAndKeepsBudgets() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXGroup", text: nil, frame: nil), 1: text("one"), 2: text("two")]
        tree.edges[0] = [1, 2]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s", limits: .init(blocks: 1))
        XCTAssertEqual(evidence.blocks.map(\.text), ["one"])
        XCTAssertFalse(tree.reads.contains(2))
        XCTAssertTrue(tree.metadataReads.contains(2))
    }
    func testBranchOverflowDropsEvidenceRatherThanFlatteningConversations() throws {
        let tree = Tree()
        tree.samples[0] = ConversationNodeSample(role: "AXWindow", text: nil, frame: nil)
        tree.edges[0] = Array(1...140)
        for id in 1...140 {
            tree.samples[id] = ConversationNodeSample(role: "AXScrollArea", text: nil, frame: nil)
            tree.edges[id] = [id + 200]; tree.samples[id + 200] = text("same")
        }
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: nil, snapshotId: "s")
        XCTAssertEqual(evidence.regions?.count, 120)
        XCTAssertTrue(evidence.truncationReasons.contains("region_budget"))
        let ids = Set(evidence.regions!.map(\.id))
        XCTAssertTrue(evidence.blocks.allSatisfy { ids.contains($0.conversationId) })
        XCTAssertTrue(evidence.regions!.allSatisfy { $0.parentId == nil || ids.contains($0.parentId!) })
        XCTAssertEqual(Set(evidence.blocks.map(\.conversationId)).count, evidence.blocks.count)
    }
}

extension ConversationTraversalTests {
    func testSearchSubrolePreservesSearchMeaningForInterpreter() throws {
        let tree = Tree()
        tree.samples = [0: ConversationNodeSample(role: "AXWindow", text: nil, frame: nil),
            1: ConversationNodeSample(role: "AXTextField", text: "private", frame: nil, isSearch: true)]
        tree.edges[0] = [1]
        let (evidence, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 1, snapshotId: "s", focusPath: [0, 1])
        XCTAssertEqual(evidence.observations?.first?.kind, "structure")
        XCTAssertEqual(evidence.observations?.first?.role, "AXSearchField")
        XCTAssertTrue(evidence.blocks.isEmpty)
    }
}
