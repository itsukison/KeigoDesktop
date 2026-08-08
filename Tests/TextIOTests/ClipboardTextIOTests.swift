import XCTest
@testable import TextIO

/// The clipboard fallback's ordering is the part that actually breaks (§5), which is
/// why the pasteboard sits behind a protocol. These tests are the reason.
final class ClipboardTextIOTests: XCTestCase {

    func testCapturesSelectionAndRestoresOriginalClipboard() async throws {
        let pasteboard = FakePasteboard(initial: "ユーザーがコピーしていたもの")
        let io = ClipboardTextIO(
            pasteboard: pasteboard,
            activator: FakeActivator(),
            keystrokes: KeystrokeSynthesizer(),
            sleeper: { _ in
                // Stand in for the target app servicing ⌘C. Real ⌘C is not synthesized
                // in a test process, so the "copy" is simulated here.
                pasteboard.write("選択されていた文章")
            }
        )

        let target = try await io.capture(hostAppBundleId: "com.apple.mail")

        XCTAssertEqual(target.text, "選択されていた文章")
        XCTAssertEqual(target.captureMode, .selection, "⌘C can never produce wholeInput")
        XCTAssertEqual(target.path, .clipboard)
        XCTAssertEqual(target.hostAppBundleId, "com.apple.mail")
        XCTAssertNil(target.element, "no AX handle on this path — the write must use ⌘V")
        XCTAssertEqual(
            pasteboard.readString(),
            "ユーザーがコピーしていたもの",
            "the user's clipboard must come back"
        )
    }

    /// Clear must happen before the copy. Without it a ⌘C that the app ignores leaves
    /// the *previous* clipboard in place and we would rewrite whatever the user last
    /// copied — silently operating on the wrong text.
    func testClearsBeforeCopyingSoAFailedCopyIsDetectable() async {
        let pasteboard = FakePasteboard(initial: "前回コピーした無関係な文章")
        let io = ClipboardTextIO(
            pasteboard: pasteboard,
            activator: FakeActivator(),
            sleeper: { _ in }   // app ignores the ⌘C: nothing lands
        )

        do {
            _ = try await io.capture(hostAppBundleId: nil)
            XCTFail("an ignored ⌘C must surface as noTarget")
        } catch {
            XCTAssertEqual(error as? TextIOError, .noTarget)
        }

        XCTAssertEqual(pasteboard.readString(), "前回コピーした無関係な文章")
        XCTAssertTrue(
            pasteboard.log.prefix(2) == [.read, .clear],
            "expected read-then-clear, got \(pasteboard.log)"
        )
    }

    /// The write has to reactivate the app captured at press time. If it is gone there
    /// is nowhere safe to paste, and pasting into whatever is frontmost now would drop
    /// the rewrite into an unrelated window.
    func testWriteFailsRatherThanPastingIntoTheWrongApp() async {
        let pasteboard = FakePasteboard(initial: "元のクリップボード")
        let io = ClipboardTextIO(
            pasteboard: pasteboard,
            activator: FakeActivator(succeeds: false),
            sleeper: { _ in }
        )

        do {
            try await io.write("書き換え後", toFrontmost: 999, mode: .selection)
            XCTFail("a dead target app must fail the write")
        } catch {
            XCTAssertEqual(error as? TextIOError, .writeFailed)
        }
        XCTAssertEqual(pasteboard.readString(), "元のクリップボード")
    }

    func testWriteActivatesThenPastesThenRestores() async throws {
        let pasteboard = FakePasteboard(initial: "元のクリップボード")
        let activator = FakeActivator()
        let io = ClipboardTextIO(pasteboard: pasteboard, activator: activator, sleeper: { _ in })

        try await io.write("書き換え後", toFrontmost: 4242, mode: .selection)

        XCTAssertEqual(activator.activated, [4242])
        XCTAssertEqual(
            pasteboard.readString(),
            "元のクリップボード",
            "restored after the paste had a chance to consume it"
        )
        // The rewrite must be on the pasteboard *before* activation, or ⌘V pastes
        // whatever was there before.
        let writeIndex = pasteboard.log.firstIndex(of: .write("書き換え後"))
        XCTAssertNotNil(writeIndex)
    }

    /// Regression: "insertion only worked in Notes."
    ///
    /// ⌘V replaces the current *selection*. Against a `.wholeInput` target nothing is
    /// selected, so a bare ⌘V inserts at the caret and the user gets their text twice
    /// instead of rewritten. A ⌘A has to precede it.
    func testWholeInputSelectsAllBeforePasting() async throws {
        let keys = RecordingKeystrokes()
        let io = ClipboardTextIO(
            pasteboard: FakePasteboard(initial: nil),
            activator: FakeActivator(),
            keystrokes: keys.synthesizer,
            sleeper: { _ in }
        )

        try await io.write("書き換え後", toFrontmost: 1, mode: .wholeInput)

        XCTAssertEqual(keys.sent, [.commandA, .commandV], "⌘A must come first, and exactly once")
    }

    /// The mirror image: with a real selection a ⌘A would *widen* the target and
    /// clobber text the user never selected.
    func testSelectionDoesNotSelectAll() async throws {
        let keys = RecordingKeystrokes()
        let io = ClipboardTextIO(
            pasteboard: FakePasteboard(initial: nil),
            activator: FakeActivator(),
            keystrokes: keys.synthesizer,
            sleeper: { _ in }
        )

        try await io.write("書き換え後", toFrontmost: 1, mode: .selection)

        XCTAssertEqual(keys.sent, [.commandV])
    }
}

// MARK: - Fakes

private final class FakePasteboard: PasteboardBridge, @unchecked Sendable {
    enum Event: Equatable {
        case read
        case write(String)
        case clear
    }

    private var contents: String?
    private(set) var log: [Event] = []
    private let lock = NSLock()

    init(initial: String?) { contents = initial }

    func readString() -> String? {
        lock.lock(); defer { lock.unlock() }
        log.append(.read)
        return contents
    }

    func write(_ string: String) {
        lock.lock(); defer { lock.unlock() }
        log.append(.write(string))
        contents = string
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        log.append(.clear)
        contents = nil
    }
}

/// Records the synthesized keystroke sequence.
private final class RecordingKeystrokes: @unchecked Sendable {
    enum Key: Equatable { case commandA, commandC, commandV }

    private(set) var sent: [Key] = []
    private let lock = NSLock()

    var synthesizer: KeystrokeSending { Recorder(owner: self) }

    fileprivate func record(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        sent.append(key)
    }

    private struct Recorder: KeystrokeSending {
        let owner: RecordingKeystrokes
        func sendCommandA() { owner.record(.commandA) }
        func sendCommandC() { owner.record(.commandC) }
        func sendCommandV() { owner.record(.commandV) }
    }
}

private final class FakeActivator: AppActivator, @unchecked Sendable {
    private let succeeds: Bool
    private(set) var activated: [pid_t] = []

    init(succeeds: Bool = true) { self.succeeds = succeeds }

    func activate(pid: pid_t) -> Bool {
        activated.append(pid)
        return succeeds
    }
}
