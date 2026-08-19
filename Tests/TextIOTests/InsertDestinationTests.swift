import DesktopRewriteKit
import XCTest
@testable import TextIO

/// §18. The verdict is a pure function over AX facts precisely so these cases can be
/// written down — gathering the facts needs a window server and another running app.
final class InsertDestinationTests: XCTestCase {

    private func facts(
        hasDestination: Bool = true,
        strategy: TextWriteStrategy = .clipboard,
        appRunning: Bool = true,
        elementWritable: Bool = false,
        elementIsField: Bool? = true,
        elementFocused: Bool = true,
        holdsCapturedText: Bool = true,
        focusReadable: Bool = true,
        redirectAvailable: Bool = false
    ) -> DestinationFacts {
        DestinationFacts(
            capturedHasDestination: hasDestination,
            capturedStrategy: strategy,
            capturedAppRunning: appRunning,
            capturedElementStillWritable: elementWritable,
            capturedElementIsField: elementIsField,
            capturedElementFocused: elementFocused,
            focusedHoldsCapturedText: holdsCapturedText,
            focusReadable: focusReadable,
            redirectAvailable: redirectAvailable
        )
    }

    func testStillFocusedFieldIsReady() {
        XCTAssertEqual(DestinationVerdict.decide(facts()), .ready)
    }

    /// An AX write is addressed to the element, so "put it back where it came from" works
    /// wherever the user has since clicked. Checking focus here would only take a working
    /// action away.
    func testSettableElementIsReadyWhereverTheCaretWent() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(
                    strategy: .ax,
                    elementWritable: true,
                    elementFocused: false,
                    holdsCapturedText: false
                )
            ),
            .ready
        )
    }

    /// Settability is re-asked rather than trusted from capture time: a destroyed element
    /// and a field that has since gone read-only must both fail it.
    func testElementThatIsNoLongerWritableFallsThrough() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(
                    strategy: .ax,
                    elementWritable: false,
                    elementFocused: false,
                    holdsCapturedText: false
                )
            ),
            .unavailable
        )
    }

    /// A clipboard write follows the keyboard, so focus is the whole question.
    func testClipboardWriteWhoseFieldLostFocusRedirects() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(elementFocused: false, holdsCapturedText: false, redirectAvailable: true)
            ),
            .redirect
        )
    }

    /// **The case the whole feature exists for**, and the one that never fired: focus
    /// moved somewhere that positively is not a text field.
    func testClipboardWriteWithFocusOnSomethingThatIsNotAFieldOffersCopy() {
        XCTAssertEqual(
            DestinationVerdict.decide(facts(elementFocused: false, holdsCapturedText: false)),
            .unavailable
        )
    }

    /// Electron and web views rebuild elements around a field that never changed, so
    /// identity alone would report the user's own compose box as gone.
    func testRebuiltElementHoldingTheSameTextIsReady() {
        XCTAssertEqual(
            DestinationVerdict.decide(facts(elementFocused: false, holdsCapturedText: true)),
            .ready
        )
    }

    func testQuitAppIsNotReady() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(appRunning: false, elementFocused: false, holdsCapturedText: false)
            ),
            .unavailable
        )
    }

    // MARK: Silence is not a negative answer

    /// AX saying nothing is an ordinary answer in the apps that are hardest to read. The
    /// first version had this backwards in both directions at once: it treated silence as
    /// permission to answer `.ready` for nearly all traffic.
    func testUnreadableFocusLeavesALiveDestinationAlone() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(elementFocused: false, holdsCapturedText: false, focusReadable: false)
            ),
            .ready
        )
    }

    /// **The captured element being asked about is not the same question as where the
    /// keyboard is**, and only the second one is unanswerable while our panel is key. A
    /// target with no element to ask has said nothing, so it must not downgrade.
    func testUnaskedFieldQuestionDoesNotDowngrade() {
        XCTAssertEqual(DestinationVerdict.decide(facts(elementIsField: nil)), .ready)
    }

    /// But silence cannot conjure a destination that never existed — the write would
    /// throw `.noDestination`.
    func testScratchComposeIsNeverReadyHoweverUnreadableFocusIs() {
        for readable in [true, false] {
            XCTAssertEqual(
                DestinationVerdict.decide(
                    facts(
                        hasDestination: false,
                        strategy: .none,
                        elementFocused: false,
                        holdsCapturedText: false,
                        focusReadable: readable
                    )
                ),
                .unavailable
            )
        }
    }

    // MARK: Captured from somewhere that cannot take text back

    /// A selection dragged across a read-only web page: captured fine, still focused,
    /// still reads back the captured text, app still running — every test below passed it
    /// and 挿入 was offered over a page that cannot be typed in. The ⌘V went nowhere and
    /// `pasteLanded` could not see it, because an `AXWebArea` has no `kAXValue`.
    func testReadOnlySelectionOffersCopyEvenThoughItStillHoldsFocus() {
        XCTAssertEqual(
            DestinationVerdict.decide(facts(elementIsField: false)),
            .unavailable
        )
    }

    /// And if the user has since clicked into somewhere that *can* take it, that is the
    /// better answer than the clipboard.
    func testReadOnlySelectionRedirectsWhenTheUserIsInAField() {
        XCTAssertEqual(
            DestinationVerdict.decide(facts(elementIsField: false, redirectAvailable: true)),
            .redirect
        )
    }

    /// Settable and "not a text control" cannot both be true — `canTakeText` answers on
    /// settability first — so the AX shortcut is never reached with a positive negative
    /// under it. Pinned so a future reordering has to say so out loud.
    func testASettableElementIsAlwaysAField() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(strategy: .ax, elementWritable: true, elementIsField: false)
            ),
            .unavailable
        )
    }

    // MARK: Scratch

    /// What makes "write a message from nothing, then click where it goes" finish — and
    /// the exact step that was observed not working: the panel stayed on コピー after the
    /// user clicked into a text box, because the probe was reading focus off the frontmost
    /// *application* element instead of system-wide.
    func testScratchComposeRedirectsToWhateverIsFocusedNow() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(
                    hasDestination: false,
                    strategy: .none,
                    elementFocused: false,
                    holdsCapturedText: false,
                    redirectAvailable: true
                )
            ),
            .redirect
        )
    }

    func testScratchComposeWithNoFieldAnywhereIsCopyOnly() {
        XCTAssertEqual(
            DestinationVerdict.decide(
                facts(
                    hasDestination: false,
                    strategy: .none,
                    elementFocused: false,
                    holdsCapturedText: false
                )
            ),
            .unavailable
        )
    }
}

/// `canTakeText`'s role handling. The signals are ordered by trust, but a *container*
/// answering them is not a weak yes — it is a wrong one.
final class TextEntryRoleTests: XCTestCase {

    /// Measured 2026-08-19: ✎ pressed in a browser with no input focused captured the
    /// page's `AXWebArea`, which answers the range and character-count questions on
    /// behalf of the document. That made `capturedIsField=true`, the verdict `.ready`,
    /// and the ⌘V went into a page that cannot be typed in.
    func testWebAreaIsNotSomethingToTypeInto() {
        XCTAssertTrue(AXTextIO.isContainerRole("AXWebArea"))
    }

    func testContainersThatAnswerTextQuestionsAreAllVetoed() {
        for role in ["AXWebArea", kAXGroupRole, kAXScrollAreaRole, kAXStaticTextRole,
                     kAXListRole, kAXOutlineRole, kAXTableRole, kAXRowRole] {
            XCTAssertTrue(AXTextIO.isContainerRole(role), role)
        }
    }

    /// Gmail's compose box is a *child* of a web area, not one, so the veto costs it
    /// nothing — the case §5 was rewritten around has to keep working.
    func testTextControlsAreNotVetoed() {
        for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"] {
            XCTAssertFalse(AXTextIO.isContainerRole(role), role)
        }
    }
}

/// The scope is what the input bar's placeholder is chosen from, and getting it wrong is
/// what let someone type 「もっと丁寧に」 at an empty compose box.
final class RewriteScopeTests: XCTestCase {

    private func target(
        text: String,
        mode: CaptureMode,
        strategy: TextWriteStrategy = .clipboard
    ) -> TextTarget {
        TextTarget(text: text, captureMode: mode, path: .ax, writeStrategy: strategy)
    }

    func testSelectionScope() {
        XCTAssertEqual(target(text: "確認してください", mode: .selection).scope, .selection)
    }

    func testWholeFieldScope() {
        XCTAssertEqual(target(text: "確認してください", mode: .wholeInput).scope, .inputField)
    }

    func testEmptyFieldIsScratchButKeepsItsDestination() {
        let empty = target(text: "", mode: .wholeInput, strategy: .ax)
        XCTAssertEqual(empty.scope, .scratch)
        XCTAssertTrue(empty.hasDestination)
    }

    func testWhitespaceOnlyFieldIsScratch() {
        XCTAssertEqual(target(text: "  \n", mode: .wholeInput).scope, .scratch)
    }

    /// §16's rule that a nil `kAXValue` is the only thing keeping ⌘A out of the Finder is
    /// now enforced by the strategy rather than by refusing to capture: a scratch target
    /// has no destination, and `TextIOCoordinator.write` refuses it outright.
    func testScratchTargetHasNoDestination() {
        let scratch = TextTarget.scratch(hostAppBundleId: "com.apple.finder")
        XCTAssertEqual(scratch.scope, .scratch)
        XCTAssertFalse(scratch.hasDestination)
        XCTAssertEqual(scratch.writeStrategy, .none)
        XCTAssertNil(scratch.element)
    }

    /// A re-resolved destination must never carry `.wholeInput`: that would send ⌘A to a
    /// field this rewrite was never read from and replace someone else's draft with it.
    func testRedirectTargetsTheCaretRatherThanTheWholeField() {
        let redirect = TextTarget.redirect(
            element: AXElementHandle(element: AXUIElementCreateApplication(1), pid: 1),
            writeStrategy: .clipboard,
            hostAppBundleId: nil
        )
        XCTAssertEqual(redirect.captureMode, .selection)
        XCTAssertTrue(redirect.hasDestination)
    }
}

/// A paste is posted, not acknowledged, so "sent" is not "landed".
final class PasteVerificationTests: XCTestCase {

    func testUnchangedFieldMeansThePasteWentNowhere() {
        XCTAssertFalse(
            AXTextIO.pasteLanded("お世話になっております。", after: "元の文章", before: "元の文章")
        )
    }

    func testFieldHoldingTheReplacementLanded() {
        XCTAssertTrue(
            AXTextIO.pasteLanded("お世話になっております。", after: "お世話になっております。", before: "元の文章")
        )
    }

    /// Looser than `writeLanded` on purpose: a field that normalises what it was given —
    /// smart quotes, a trimmed newline, an autocomplete — did accept the paste.
    func testAnyChangeAtAllCountsAsLanded() {
        XCTAssertTrue(AXTextIO.pasteLanded("\"quoted\"", after: "“quoted”", before: "original"))
    }

    /// The pasted text landing inside a larger field is the `.selection` case.
    func testReplacementInsideALargerFieldLanded() {
        XCTAssertTrue(
            AXTextIO.pasteLanded("恐れ入りますが", after: "前略 恐れ入りますが 以上", before: "前略 すみませんが 以上")
        )
    }

    /// Nothing readable before *or* after is the one case that cannot be judged, and
    /// pasting again over a write that did land would duplicate the user's text.
    func testUnreadableBeforeAndUnchangedAfterIsNotAFailure() {
        XCTAssertTrue(AXTextIO.pasteLanded("something", after: "something", before: nil))
    }
}
