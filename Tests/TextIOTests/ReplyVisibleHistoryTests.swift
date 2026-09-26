import XCTest
@testable import TextIO

final class ReplyVisibleHistoryTests: XCTestCase {
    private func fixture() -> ConversationTraversalTests.Tree {
        let tree = ConversationTraversalTests.Tree()
        tree.samples[0] = .init(role: "AXWindow", text: nil, frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        tree.samples[1] = .init(role: "AXGroup", text: nil, frame: CGRect(x: 300, y: 100, width: 600, height: 700))
        tree.samples[2] = .init(role: "AXTextArea", text: "private draft", frame: CGRect(x: 310, y: 700, width: 550, height: 80))
        tree.samples[3] = .init(role: "AXList", text: nil, frame: CGRect(x: 300, y: 150, width: 600, height: 540))
        tree.edges = [0: [1], 1: [3, 2]]
        return tree
    }
    func testCollapsedOldHistoryCannotConsumeTextBudgetBeforeCurrentMessage() throws {
        let tree = fixture()
        tree.edges[3] = Array(10...309) + [400]
        for id in 10...309 {
            tree.samples[id] = .init(role: "AXStaticText", text: "Old history \(id)", frame: CGRect(x: 320, y: 150, width: 400, height: 1))
        }
        tree.samples[400] = .init(role: "AXStaticText", text: "Can you send the updated plan?", frame: CGRect(x: 320, y: 620, width: 450, height: 60))
        let (capture, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
        XCTAssertEqual(capture.blocks.map(\.text), ["Can you send the updated plan?"])
        XCTAssertEqual(capture.diagnostics?.clippedTextNodes, 300)
        XCTAssertEqual(capture.diagnostics?.textReads, 1)
        XCTAssertEqual(observations.filter(\.clipped).count, 300)
        XCTAssertFalse(capture.truncationReasons.contains("missing_current_history"))
        XCTAssertFalse(tree.reads.contains(2))
    }
    func testNearComposerSurvivesWhenEarlierSubstantialTextExceedsBlockBudget() throws {
        let tree = fixture()
        tree.edges[3] = Array(10...89) + [400]
        for id in 10...89 {
            tree.samples[id] = .init(role: "AXStaticText", text: "Earlier \(id)", frame: CGRect(x: 320, y: 150, width: 400, height: 20))
        }
        tree.samples[400] = .init(role: "AXStaticText", text: "Current incoming", frame: CGRect(x: 320, y: 630, width: 400, height: 40))
        let (capture, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
        XCTAssertEqual(capture.blocks.count, 60)
        XCTAssertTrue(capture.blocks.contains { $0.text == "Current incoming" })
        XCTAssertTrue(capture.truncationReasons.contains("block_budget"))
        XCTAssertFalse(capture.truncationReasons.contains("missing_current_history"))
        XCTAssertEqual(tree.reads.first, 400)
    }
    func testThinWrapperDoesNotHideVisibleChildAndOnePixelIntersectionIsExcluded() throws {
        let tree = fixture()
        tree.samples[4] = .init(role: "AXScrollArea", text: nil, frame: CGRect(x: 300, y: 150, width: 600, height: 540))
        tree.samples[5] = .init(role: "AXGroup", text: nil, frame: CGRect(x: 320, y: 150, width: 400, height: 1))
        tree.samples[6] = .init(role: "AXStaticText", text: "Clipped", frame: CGRect(x: 320, y: 131, width: 400, height: 20))
        tree.samples[7] = .init(role: "AXStaticText", text: "Visible descendant", frame: CGRect(x: 320, y: 620, width: 400, height: 40))
        tree.edges[3] = [4]; tree.edges[4] = [5, 6]; tree.edges[5] = [7]
        let (capture, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
        XCTAssertEqual(capture.blocks.map(\.text), ["Visible descendant"])
        XCTAssertFalse(tree.reads.contains(6))
    }
    func testMissingOrUnreadCurrentTextHasSpecificCaptureFailure() throws {
        for value in [String?.none, String(repeating: "x", count: 12001)] {
            let tree = fixture()
            tree.edges[3] = [4]
            tree.samples[4] = .init(role: "AXStaticText", text: value, frame: CGRect(x: 320, y: 620, width: 400, height: 40))
            let (capture, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
            XCTAssertTrue(capture.truncationReasons.contains("missing_current_history"))
            XCTAssertEqual(capture.diagnostics?.skippedCurrentTextNodes, 1)
        }
    }

    /// Synthetic text with the latest LinkedIn export's window/composer/header geometry.
    private func linkedInFixture(spacer: String?) -> ConversationTraversalTests.Tree {
        let tree = fixture()
        tree.samples[0] = .init(role: "AXWindow", text: nil, frame: CGRect(x: 0, y: 122, width: 1400, height: 900))
        tree.samples[1] = .init(role: "AXGroup", text: nil, frame: CGRect(x: 700, y: 300, width: 450, height: 700))
        tree.samples[2] = .init(role: "AXTextArea", text: "private draft", frame: CGRect(x: 713, y: 869, width: 410, height: 100))
        tree.samples[3] = .init(role: "AXList", text: nil, frame: CGRect(x: 700, y: 300, width: 450, height: 540))
        tree.edges[3] = [4, 5, 6, 7]
        tree.samples[4] = .init(role: "AXStaticText", text: "•", frame: CGRect(x: 927, y: 708, width: 7, height: 16))
        tree.samples[5] = .init(role: "AXStaticText", text: spacer, frame: CGRect(x: 933, y: 708, width: 4, height: 16))
        tree.samples[6] = .init(role: "AXStaticText", text: "1:53 PM", frame: CGRect(x: 936, y: 708, width: 47, height: 16))
        tree.samples[7] = .init(role: "AXStaticText", text: "Please submit by Tuesday.", frame: CGRect(x: 757, y: 735, width: 338, height: 78))
        return tree
    }

    func testReadableBlankTimestampSpacerDoesNotInvalidateRetainedMessage() throws {
        for spacer in ["", " ", "\n\t", "\u{00a0}"] {
            let tree = linkedInFixture(spacer: spacer)
            let (capture, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
            XCTAssertEqual(capture.blocks.map(\.text), ["•", "1:53 PM", "Please submit by Tuesday."])
            XCTAssertFalse(capture.truncationReasons.contains("missing_current_history"))
            XCTAssertEqual(capture.diagnostics?.skippedCurrentTextNodes, 0)
            XCTAssertEqual(observations.first { $0.bounds == tree.samples[5]?.frame }?.textDisposition, "empty_text")
            XCTAssertEqual(observations.filter { $0.textDisposition == "retained" }.count, 3)
            XCTAssertFalse(tree.reads.contains(2))
        }
    }

    func testUnreadableAndBudgetOmittedNeighborsStillFailWithRetainedMessage() throws {
        for (spacer, expected) in [(String?.none, "text_unreadable"), (String(repeating: "x", count: 12001), "text_budget")] {
            let tree = linkedInFixture(spacer: spacer)
            let (capture, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
            XCTAssertTrue(capture.blocks.contains { $0.text == "Please submit by Tuesday." })
            XCTAssertTrue(capture.truncationReasons.contains("missing_current_history"))
            XCTAssertEqual(capture.diagnostics?.skippedCurrentTextNodes, 1)
            XCTAssertEqual(observations.first { $0.bounds == tree.samples[5]?.frame }?.textDisposition, expected)
        }
        let tree = linkedInFixture(spacer: " ")
        let (capture, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2], limits: .init(blocks: 1))
        XCTAssertEqual(capture.blocks.map(\.text), ["Please submit by Tuesday."])
        XCTAssertTrue(capture.truncationReasons.contains("missing_current_history"))
        XCTAssertEqual(observations.filter { $0.textDisposition == "block_budget" }.count, 3)
    }

    private struct ChangedReadTree: ConversationTreeAccess {
        let base: ConversationTraversalTests.Tree
        let replacement: ConversationNodeSample?
        func metadata(_ node: Int) -> ConversationNodeSample? { base.metadata(node) }
        func composer(_ node: Int) -> ConversationNodeSample? { base.composer(node) }
        func sample(_ node: Int) -> ConversationNodeSample? { node == 5 ? replacement : base.sample(node) }
        func children(_ node: Int, offset: Int, limit: Int) -> (nodes: [Int], truncated: Bool, errorCode: Int?) {
            base.children(node, offset: offset, limit: limit)
        }
    }

    func testBlankSampleCannotExcuseReadFailuresOrChangedNodes() throws {
        let base = linkedInFixture(spacer: " ")
        let frame = base.samples[5]!.frame!
        let cases: [(ConversationNodeSample?, String)] = [
            (nil, "sample_unreadable"),
            (.init(role: "AXHeading", text: " ", frame: frame), "role_changed"),
            (.init(role: "AXStaticText", text: " ", frame: frame, isEditable: true), "editing_changed"),
            (.init(role: "AXStaticText", text: " ", frame: frame.offsetBy(dx: 1, dy: 0)), "geometry_changed"),
            (.init(role: "AXStaticText", text: " ", frame: frame, failedAttributes: ["AXValue"], axErrorCodes: [-25204]), "text_unreadable"),
        ]
        for (sample, expected) in cases {
            let tree = ChangedReadTree(base: base, replacement: sample)
            let (capture, observations) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
            XCTAssertTrue(capture.blocks.contains { $0.text == "Please submit by Tuesday." })
            XCTAssertTrue(capture.truncationReasons.contains("missing_current_history"), expected)
            XCTAssertEqual(capture.diagnostics?.skippedCurrentTextNodes, 1)
            XCTAssertEqual(observations.first { $0.bounds == frame }?.textDisposition, expected)
            if sample?.axErrorCodes.isEmpty == false {
                XCTAssertTrue(capture.diagnostics?.axErrorCodes.contains(-25204) == true)
                XCTAssertEqual(observations.first { $0.bounds == frame }?.failedAttributes, ["AXValue"])
            }
        }
    }

    func testOnlyBlankHistoryStillRequiresFreshCapture() throws {
        let tree = fixture()
        tree.edges[3] = [4]
        tree.samples[4] = .init(role: "AXStaticText", text: " ", frame: CGRect(x: 320, y: 620, width: 400, height: 40))
        let (capture, _) = try ConversationTraversal.read(tree: tree, root: 0, excluded: 2, snapshotId: "s", focusPath: [0, 1, 2])
        XCTAssertTrue(capture.blocks.isEmpty)
        XCTAssertEqual(capture.diagnostics?.skippedCurrentTextNodes, 0)
        XCTAssertTrue(capture.truncationReasons.contains("missing_current_history"))
    }
}
