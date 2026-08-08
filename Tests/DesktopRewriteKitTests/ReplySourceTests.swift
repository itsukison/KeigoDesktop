import XCTest
@testable import DesktopRewriteKit

/// The arming rules for reply mode (§16). `ClipboardWatcher` is untestable — it needs a
/// real pasteboard and a runloop — so everything that *decides* lives here instead.
final class ReplySourceTests: XCTestCase {

    func testShortCopyIsNotAReplySource() {
        XCTAssertNil(ReplySource(copied: "#5a57ba"))
        XCTAssertNil(ReplySource(copied: "了解です"))
        XCTAssertNil(ReplySource(copied: "MainModel"))
    }

    /// The threshold is a character count and nothing more, so a long path or URL does
    /// arm the bar. Pinned rather than worked around: the alternative is guessing at the
    /// shape of the text, and ✕ already answers a bar that appeared when it need not
    /// have. If this ever starts mattering, this is the test that has to change first.
    func testLongNonMessageCopyStillArms() {
        XCTAssertNotNil(ReplySource(copied: "https://github.com/example/repo/pull/1421"))
        XCTAssertNotNil(ReplySource(copied: "npm run build"))
    }

    /// The number is set by Japanese, not by English. 「明日の打ち合わせは大丈夫でしょうか。」
    /// is 18 characters and an entirely ordinary message to reply to, so a threshold
    /// tuned by eye against ASCII noise — 20 was tried — excludes the real cases.
    func testOrdinaryOneLineJapaneseMessageArms() {
        XCTAssertNotNil(ReplySource(copied: "明日の打ち合わせは大丈夫でしょうか。"))
        XCTAssertNotNil(ReplySource(copied: "本日の資料を送っていただけますか。"))
    }

    func testBlankCopyIsNotAReplySource() {
        XCTAssertNil(ReplySource(copied: ""))
        XCTAssertNil(ReplySource(copied: "   \n\n\t  "))
    }

    /// Whitespace is trimmed *before* the length check, so a short message padded with
    /// newlines — which is what selecting a paragraph in Mail produces — does not sneak
    /// past the threshold on its padding.
    func testLengthIsMeasuredAfterTrimming() {
        XCTAssertNil(ReplySource(copied: "\n\n   短いです   \n\n"))
    }

    func testMessageLengthCopyArms() throws {
        let message = "お世話になっております。明日の打ち合わせの時間を変更できますか。"
        let source = try XCTUnwrap(ReplySource(copied: message))
        XCTAssertEqual(source.text, message)
    }

    func testTrimmedTextIsWhatGoesOverTheWire() throws {
        let source = try XCTUnwrap(
            ReplySource(copied: "  \n本日はお時間をいただきありがとうございました。\n  ")
        )
        XCTAssertEqual(source.text, "本日はお時間をいただきありがとうございました。")
    }

    /// The pill is one line, so the newlines have to go. Cutting at the first one
    /// instead — which is what `lineLimit(1)` does on its own — would show a greeting
    /// and nothing else, since that is how the messages worth replying to start.
    func testContextTextIsFlattenedToOneLine() throws {
        let source = try XCTUnwrap(
            ReplySource(copied: "お世話になっております。\n\n明日の打ち合わせですが、14時に変更できますか。")
        )
        XCTAssertEqual(
            source.contextText,
            "お世話になっております。 明日の打ち合わせですが、14時に変更できますか。"
        )
        XCTAssertFalse(source.contextText.contains("\n"))
    }

    /// The wire payload keeps everything the display drops — `replyTo` is what the
    /// model composes against, and flattening it there would lose the message's shape.
    func testFlatteningDoesNotReachTheWirePayload() throws {
        let message = "一行目です。\n二行目です。"
        let source = try XCTUnwrap(ReplySource(copied: message))
        XCTAssertEqual(source.text, message)
    }

    /// The pill truncates visually; this bound only keeps SwiftUI from being handed a
    /// 10,000-character string to lay out. The full text still goes over the wire.
    func testContextTextIsBoundedForLayout() throws {
        let long = String(repeating: "あ", count: 5_000)
        let source = try XCTUnwrap(ReplySource(copied: long))
        XCTAssertEqual(source.contextText.count, ReplySource.contextCharacters + 1)
        XCTAssertTrue(source.contextText.hasSuffix("…"))
        XCTAssertEqual(source.text.count, 5_000, "the wire payload is not truncated")
    }

    func testExpiryIsMeasuredFromTheCopy() throws {
        let copiedAt = Date(timeIntervalSince1970: 1_000_000)
        let source = try XCTUnwrap(
            ReplySource(copied: "ご連絡ありがとうございます。確認いたします。", at: copiedAt)
        )
        XCTAssertFalse(source.isExpired(at: copiedAt))
        XCTAssertFalse(source.isExpired(at: copiedAt.addingTimeInterval(ReplySource.lifetime - 1)))
        XCTAssertTrue(source.isExpired(at: copiedAt.addingTimeInterval(ReplySource.lifetime)))
    }
}
