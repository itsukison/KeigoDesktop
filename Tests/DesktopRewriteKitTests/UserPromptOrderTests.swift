import XCTest
@testable import DesktopRewriteKit

final class UserPromptOrderTests: XCTestCase {
    func testMovingSecondaryUpReplacesMain() {
        let oldMain = make("敬語", slot: .main, order: 0)
        let english = make("英訳", slot: .sub, order: 0)

        let moved = UserPromptOrder.moving(
            [oldMain, english],
            id: english.id,
            by: -1
        )

        XCTAssertEqual(moved?.map(\.title), ["英訳", "敬語"])
        XCTAssertEqual(moved?.map(\.slot), [.main, .sub])
        XCTAssertEqual(moved?.map(\.sortOrder), [0, 0])
    }

    func testMovingMainDownPromotesNextRow() {
        let first = make("A", slot: .main, order: 0)
        let second = make("B", slot: .sub, order: 0)
        let third = make("C", slot: .sub, order: 1)

        let moved = UserPromptOrder.moving(
            [first, second, third],
            id: first.id,
            by: 1
        )

        XCTAssertEqual(moved?.map(\.title), ["B", "A", "C"])
        XCTAssertEqual(moved?.map(\.slot), [.main, .sub, .sub])
    }

    func testPromotingAfterMainDeletion() {
        let remaining = UserPromptOrder.normalized([
            make("要約", slot: .sub, order: 2),
            make("英訳", slot: .sub, order: 7),
        ])

        XCTAssertEqual(remaining.map(\.slot), [.main, .sub])
        XCTAssertEqual(remaining.map(\.sortOrder), [0, 0])
    }

    func testMovingPastBoundaryIsNoOp() {
        let prompt = make("敬語", slot: .main, order: 0)
        XCTAssertNil(UserPromptOrder.moving(
            [prompt],
            id: prompt.id,
            by: -1
        ))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: prompt.id, by: 1))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: prompt.id, by: 2))
    }

    func testEveryDragInsertionGap() throws {
        var prompts = (0..<4).map { make("Button \($0)", slot: $0 == 0 ? .main : .sub, order: max(0, $0 - 1)) }
        prompts[1].isEnabled = false
        for source in prompts.indices {
            for gap in 0...prompts.count {
                let destination = gap > source ? gap - 1 : gap
                let moved = UserPromptOrder.moving(prompts, id: prompts[source].id, toInsertionIndex: gap)
                if source == destination {
                    XCTAssertNil(moved, "Dropping next to the source should not save")
                    continue
                }
                let result = try XCTUnwrap(moved)
                var expected = prompts.map(\.id)
                expected.insert(expected.remove(at: source), at: destination)
                XCTAssertEqual(result.map(\.id), expected)
                XCTAssertEqual(result.map(\.slot), [.main, .sub, .sub, .sub])
                XCTAssertEqual(result.map(\.sortOrder), [0, 0, 1, 2])
                for row in result {
                    var original = try XCTUnwrap(prompts.first { $0.id == row.id })
                    original.slot = row.slot
                    original.sortOrder = row.sortOrder
                    XCTAssertEqual(row, original, "Reordering must preserve content and visibility")
                }
            }
        }
    }

    func testDragRejectsStaleOrInvalidDestinations() {
        let prompt = make("A", slot: .main, order: 0)
        XCTAssertNil(UserPromptOrder.moving([], id: prompt.id, toInsertionIndex: 0))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: UUID(), toInsertionIndex: 0))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: prompt.id, toInsertionIndex: -1))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: prompt.id, toInsertionIndex: 2))
        XCTAssertNil(UserPromptOrder.moving([prompt], id: prompt.id, toInsertionIndex: 1))
    }

    private func make(
        _ title: String,
        slot: UserPrompt.Slot,
        order: Int
    ) -> UserPrompt {
        UserPrompt(slot: slot, title: title, prompt: "p", sortOrder: order)
    }
}
