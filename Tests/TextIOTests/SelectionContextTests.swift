import XCTest
@testable import TextIO

/// `CFRange` from AX is measured in UTF-16 code units, and the surrounding-context
/// slices come out of the field's full value. Doing that arithmetic in `Character`
/// offsets is how kanji and emoji get cut in half — the slice would land mid
/// surrogate pair and the model would receive replacement characters.
final class SelectionContextTests: XCTestCase {

    func testSlicesContextAroundASelection() {
        let whole = "お世話になっております。資料を送ります。よろしくお願いします。"
        // "お世話になっております。" is 12 UTF-16 units, so the selection
        // "資料を送ります。" starts at 12 and is 8 units long.
        let range = CFRange(location: 12, length: 8)

        let (before, after) = AXTextIO.context(around: range, in: whole)

        XCTAssertEqual(before, "お世話になっております。")
        XCTAssertEqual(after, "よろしくお願いします。")
    }

    /// Emoji outside the BMP are two UTF-16 units. A range that ends on the boundary
    /// must not split one.
    func testDoesNotSplitSurrogatePairs() {
        let whole = "承知しました🙇‍♂️ありがとうございます"
        let selected = "承知しました"
        let range = CFRange(location: 0, length: selected.utf16.count)

        let (before, after) = AXTextIO.context(around: range, in: whole)

        XCTAssertNil(before, "nothing precedes offset 0")
        XCTAssertEqual(after, "🙇‍♂️ありがとうございます")
        XCTAssertFalse(
            after?.unicodeScalars.contains("\u{FFFD}") ?? false,
            "a split surrogate would decode to U+FFFD"
        )
    }

    func testReturnsNilWhenThereIsNoSurroundingText() {
        let whole = "了解"
        let range = CFRange(location: 0, length: 2)
        let (before, after) = AXTextIO.context(around: range, in: whole)
        XCTAssertNil(before)
        XCTAssertNil(after)
    }

    /// A caret with no selection is the `.wholeInput` case; context is meaningless and
    /// must not be fabricated from a zero-length range.
    func testEmptySelectionStillSlicesAroundTheCaret() {
        let whole = "abcdef"
        let (before, after) = AXTextIO.context(around: CFRange(location: 3, length: 0), in: whole)
        XCTAssertEqual(before, "abc")
        XCTAssertEqual(after, "def")
    }

    /// AX can hand back a range that no longer matches the value it also handed back
    /// (the app mutated between the two calls). That must degrade to nil, not trap.
    func testToleratesRangeBeyondTheValue() {
        let (before, after) = AXTextIO.context(
            around: CFRange(location: 500, length: 10),
            in: "短い"
        )
        XCTAssertNil(before)
        XCTAssertNil(after)
    }

    func testToleratesNegativeLocation() {
        let (before, after) = AXTextIO.context(
            around: CFRange(location: -1, length: 4),
            in: "text"
        )
        XCTAssertNil(before)
        XCTAssertNil(after)
    }

    /// The window is bounded so a 40-page document does not get shipped as "context".
    func testClampsContextToTheWindow() {
        let filler = String(repeating: "あ", count: 2000)
        let whole = filler + "対象" + filler
        let range = CFRange(location: 2000, length: 2)

        let (before, after) = AXTextIO.context(around: range, in: whole)

        XCTAssertEqual(before?.count, 600)
        XCTAssertEqual(after?.count, 600)
    }
}
