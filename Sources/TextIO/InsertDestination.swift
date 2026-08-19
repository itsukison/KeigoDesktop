import Foundation

/// Where an Insert would actually land, asked *before* the button is pressed (§18).
///
/// The old flow captured a destination and then trusted it for the whole life of the
/// result panel. Everything in between — switching app, clicking another field, closing
/// the tab — invalidated it silently, and the write either landed nowhere or, for a
/// `.wholeInput` clipboard write, sent ⌘A to a field the rewrite was never read from.
public enum DestinationVerdict: String, Equatable, Sendable {
    /// The captured destination is still good. Write as captured.
    case ready
    /// It is gone, but the user is in a different field that can take text. Insert
    /// there instead, at the caret.
    case redirect
    /// Nowhere to write. Copy is the only honest action, and the panel says so.
    case unavailable
}

/// The AX facts the verdict is made from, separated so the decision is a pure function.
///
/// Gathering these needs synchronous cross-process AX calls that cannot run in a test;
/// choosing between them is the part that has edge cases. Same split as
/// `AXTextIO.writeLanded` and `AXTextIO.context(around:in:)`.
public struct DestinationFacts: Equatable, Sendable {
    /// The captured target had somewhere to write at capture time — i.e. it is not a
    /// scratch compose.
    public var capturedHasDestination: Bool
    public var capturedStrategy: TextWriteStrategy
    public var capturedAppRunning: Bool
    /// The captured element still accepts the write it was captured for: `kAXSelectedText`
    /// settable, re-asked now. A destroyed element and a field that has since gone
    /// read-only both fail it, and both passed the "does it answer a read" test it
    /// replaced.
    public var capturedElementStillWritable: Bool
    /// The captured element is still a text control at all: `canTakeText`, re-asked now.
    ///
    /// **Tri-state, and nil is not a "no".** A captured element that positively is not a
    /// text control — a read-only web area a selection was taken from — can never accept
    /// the write, whatever else is true of it. But a target with no element to ask (the
    /// clipboard path) has said nothing, and §18's rule is that silence never downgrades.
    public var capturedElementIsField: Bool?
    /// The element the user's keyboard was last seen on **is** the one we captured.
    public var capturedElementFocused: Bool
    /// The focused element reads back the text we captured. Electron and web views
    /// rebuild elements around a field that never changed, so identity alone reports the
    /// user's own compose box as gone.
    public var focusedHoldsCapturedText: Bool
    /// There is a usable reading of where the user's keyboard is — see `UserFocus`.
    ///
    /// **False is not "nothing is focused"**, it is "nobody could be asked": either AX
    /// would not say, or every reading so far was taken while our own key panel owned
    /// focus and therefore answered about us. Both are ordinary, and neither is evidence.
    ///
    /// **This is deliberately not a live reading.** `focusIsSelf` used to be a fact here
    /// and the verdict fell open on it, which made the whole probe a no-op: the result
    /// panel is key for its entire life, so the live answer was always "us". The reading
    /// is now taken from the last moment the question could be asked and remembered.
    public var focusReadable: Bool
    /// That reading is a field that can take text — and is neither ours nor a password box.
    public var redirectAvailable: Bool

    public init(
        capturedHasDestination: Bool,
        capturedStrategy: TextWriteStrategy,
        capturedAppRunning: Bool,
        capturedElementStillWritable: Bool,
        capturedElementIsField: Bool?,
        capturedElementFocused: Bool,
        focusedHoldsCapturedText: Bool,
        focusReadable: Bool,
        redirectAvailable: Bool
    ) {
        self.capturedHasDestination = capturedHasDestination
        self.capturedStrategy = capturedStrategy
        self.capturedAppRunning = capturedAppRunning
        self.capturedElementStillWritable = capturedElementStillWritable
        self.capturedElementIsField = capturedElementIsField
        self.capturedElementFocused = capturedElementFocused
        self.focusedHoldsCapturedText = focusedHoldsCapturedText
        self.focusReadable = focusReadable
        self.redirectAvailable = redirectAvailable
    }
}

extension DestinationVerdict {

    /// Ordered by how the write actually behaves, because that is the only thing that
    /// decides whether Insert can work:
    ///
    ///   1. An **AX write is addressed to the element** and does not need focus. If that
    ///      element still takes a write, Insert puts the text back where it came from no
    ///      matter where the user has since clicked — and "put it back" is what Insert
    ///      means. Focus is irrelevant here and checking it would only take a working
    ///      action away.
    ///   2. A **clipboard write follows the keyboard**: it reactivates the captured app
    ///      and pastes into whatever has focus. So focus is the whole question, and the
    ///      captured element still holding it — by identity, or by still reading back the
    ///      text we took — is what makes it safe.
    ///   3. Otherwise the user is somewhere else. If that somewhere is a field, offer to
    ///      insert *there*; if it is positively not a field, offer Copy.
    ///
    /// **Unknown is not "no", and that distinction is the whole of the fail-open policy.**
    /// A wrong `.unavailable` costs one ⌘V; a wrong `.ready` is the bug this exists for —
    /// but the first version treated *silence* from AX as a positive reading in the other
    /// direction and answered `.ready` for nearly all traffic, so コピー never appeared
    /// once. Silence now leaves a live destination alone and nothing else.
    public static func decide(_ facts: DestinationFacts) -> DestinationVerdict {
        // A scratch compose never had a destination, so anything the user has clicked
        // into since is a better answer than the clipboard — and `.ready` is not merely
        // conservative here, it is impossible: the write would throw `.noDestination`.
        guard facts.capturedHasDestination else {
            return facts.redirectAvailable ? .redirect : .unavailable
        }

        // Capture asks whether an element has *text*, never whether it could take any
        // back: a selection dragged across a read-only web page reads perfectly and is
        // captured with the clipboard strategy, and every later test then passed it —
        // the element is alive, it is still where the keyboard is, and it still reads
        // back the captured text. So 挿入 was offered over a page that cannot be typed
        // in, the ⌘V went nowhere, and `pasteLanded` could not see it because a web area
        // has no `kAXValue` to compare. A positive "that is not a text control" is the
        // one reading that settles it, and it belongs ahead of everything below.
        if facts.capturedElementIsField == false {
            return facts.redirectAvailable ? .redirect : .unavailable
        }

        if facts.capturedStrategy == .ax, facts.capturedElementStillWritable { return .ready }

        guard facts.capturedAppRunning else {
            return facts.redirectAvailable ? .redirect : .unavailable
        }

        if facts.capturedElementFocused || facts.focusedHoldsCapturedText { return .ready }

        // Nobody could be asked where the keyboard is. Leaving a destination that may
        // well still work is the smaller error than retiring it on an unasked question.
        if !facts.focusReadable { return .ready }

        return facts.redirectAvailable ? .redirect : .unavailable
    }
}
