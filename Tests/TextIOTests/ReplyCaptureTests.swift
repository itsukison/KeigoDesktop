import XCTest
@testable import TextIO

final class ReplyCaptureTests: XCTestCase {
    func testCopiedIncomingSelectionIsContextNotDraft() {
        let message = "Josh: @itsuki is it possible for you to get this done today"
        XCTAssertEqual(
            AXTextIO.replyCaptureDisposition(
                copiedMessage: message,
                selectedText: "  \(message)\n",
                wholeValue: message,
                canTakeText: true
            ),
            .copiedSource
        )
    }

    func testPartialSelectionInDraftUsesWholeDraft() {
        XCTAssertEqual(
            AXTextIO.replyCaptureDisposition(
                copiedMessage: "Josh: Can you finish this today?",
                selectedText: "today",
                wholeValue: "Yes, I can finish this today.",
                canTakeText: true
            ),
            .wholeDraft("Yes, I can finish this today.")
        )
    }

    func testBlankReplyFieldIsAWholeDraftWithDestination() {
        XCTAssertEqual(
            AXTextIO.replyCaptureDisposition(
                copiedMessage: "Josh: Can you finish this today?",
                selectedText: "",
                wholeValue: "",
                canTakeText: true
            ),
            .wholeDraft("")
        )
    }

    func testReadableNonTextContentIsNotTreatedAsAReplyDraft() {
        XCTAssertEqual(
            AXTextIO.replyCaptureDisposition(
                copiedMessage: "Josh: Can you finish this today?",
                selectedText: nil,
                wholeValue: "Inbox",
                canTakeText: false
            ),
            .scratch
        )
    }
}
