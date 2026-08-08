import AppKit

/// The always-on-screen window. Pill, hover row and input bar are all this one
/// panel at different sizes (§4).
///
/// **The load-bearing detail is `canBecomeKey`.** If hovering the pill steals focus,
/// the user's text field loses `AXFocused` and we lose the target we are about to
/// write into. `becomesKeyOnlyIfNeeded` is not enough on its own — a `TextField`
/// inside the content view counts as "needed" and would pull focus the moment the
/// row expands. So key-ness is an explicit gate that only the input bar opens.
final class PillPanel: NSPanel {

    /// Opened only for the input bar state, and only after the target has already
    /// been captured.
    var acceptsKey = false {
        didSet {
            guard !acceptsKey, isKeyWindow else { return }
            // Handing focus back explicitly; letting it lapse leaves the user's app
            // active but with no first responder, so their next keystroke vanishes.
            resignKey()
        }
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true

        // Over normal windows, below menu-bar dropdowns.
        level = .statusBar
        // Survives Spaces switches and full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        // §8 deviation 1. AppKit derives this from the content's alpha channel and
        // draws it *outside* the frame. A SwiftUI `.shadow` cannot: the window is
        // sized exactly to the pill, so it gets clipped to the frame and the only
        // part that survives is a grey smear in the corners.
        // Needs `invalidateShadow()` whenever the content resizes.
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
    }
}
