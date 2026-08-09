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

    private func make(
        _ title: String,
        slot: UserPrompt.Slot,
        order: Int
    ) -> UserPrompt {
        UserPrompt(slot: slot, title: title, prompt: "p", sortOrder: order)
    }
}
