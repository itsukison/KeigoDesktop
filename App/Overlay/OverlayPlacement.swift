import AppKit

/// Where the pill sits, and how that survives a display being unplugged (§4).
enum OverlayPlacement {

    /// Stored as an offset from the work area's origin, never as an absolute point.
    /// An absolute point strands the pill off-screen the moment an external display
    /// goes away.
    private static let offsetKey = "overlay.pill.offsetFromVisibleFrameOrigin"

    /// The screen under the mouse cursor, falling back to `.main`. Same rule
    /// `prompt/src/core/window-manager.js` `positionOverlay()` uses.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screen a window is actually **on** — the one containing its centre.
    ///
    /// Deliberately not `activeScreen()`. The position poll compares the work area of
    /// whichever screen the *mouse* is over, so on a two-display setup merely moving
    /// the cursor to the other display changed the answer, triggered a re-anchor, and
    /// clamped the bar onto that display at an X carried over from the one it left.
    /// The bar is draggable: it belongs where it was put, not where the pointer is.
    static func screen(containing frame: NSRect) -> NSScreen {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? activeScreen()
    }

    /// Keeps a frame inside the work area of whichever screen it is on.
    ///
    /// Resolved from the frame rather than `NSWindow.screen`, which returns nil once a
    /// window is fully off-screen — precisely the case a clamp exists to handle.
    static func clampToWorkArea(_ frame: NSRect) -> NSRect {
        clamp(frame, to: workArea(on: screen(containing: frame)))
    }

    /// Places an auxiliary panel — the generating capsule, the result card — on the
    /// bar's bottom edge and inside the work area.
    ///
    /// The clamp is the point. These were centred on the bar with no bounds check at
    /// all, and the bar is draggable with a persisted position, so parking it near a
    /// screen edge left a 420 pt result card hanging off the side.
    static func auxiliaryFrame(size: NSSize, anchoredTo bar: NSRect) -> NSRect {
        clampToWorkArea(
            NSRect(x: bar.midX - size.width / 2, y: bar.minY, width: size.width, height: size.height)
        )
    }

    /// `visibleFrame`, corrected at the bottom edge.
    ///
    /// **`visibleFrame` on its own is wrong, and not marginally.** Measured on a
    /// 1920×1080 display while a full-screen space had the Dock hidden: the Dock's own
    /// AX element put its top edge at the screen's bottom — gone — while `visibleFrame`
    /// still reported `minY = 78`. No notification fires for that, and polling
    /// `visibleFrame` cannot see it either, because the value never changes. So the
    /// bar hung 78 pt above the bottom of every full-screen app.
    ///
    /// `DockProbe` decides whether the Dock is really down there. Only then is
    /// `visibleFrame.minY` trusted; otherwise the work area runs to the screen edge.
    static func workArea(on screen: NSScreen) -> NSRect {
        var area = screen.visibleFrame
        guard !DockProbe.occupiesBottom(of: screen) else { return area }
        area.size.height += area.minY - screen.frame.minY
        area.origin.y = screen.frame.minY
        return area
    }

    /// The bottom edge. Every reposition goes through here — the old `reframe`
    /// carried the previous frame's `minY` forward instead, so the Y computed at
    /// launch was the Y forever.
    static func anchorY(on screen: NSScreen) -> CGFloat {
        workArea(on: screen).minY + (savedOffset()?.y ?? Tokens.Geometry.bottomInset)
    }

    static func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let area = workArea(on: screen)

        if let offset = savedOffset() {
            let proposed = NSRect(
                x: area.origin.x + offset.x,
                y: area.origin.y + offset.y,
                width: size.width,
                height: size.height
            )
            // A saved offset from a wider display can still land outside a narrower
            // one, so clamp rather than trust it.
            if area.intersects(proposed) {
                return clamp(proposed, to: area)
            }
        }

        return NSRect(
            x: area.midX - size.width / 2,
            y: anchorY(on: screen),
            width: size.width,
            height: size.height
        )
    }

    /// Keeps the same centre point while the window changes size, so expanding the
    /// row grows it symmetrically instead of dragging it sideways. The Y is *not*
    /// carried over from `current` — see `anchorY`.
    static func reframe(_ current: NSRect, to size: NSSize, on screen: NSScreen) -> NSRect {
        let proposed = NSRect(
            x: current.midX - size.width / 2,
            y: anchorY(on: screen),
            width: size.width,
            height: size.height
        )
        return clamp(proposed, to: workArea(on: screen))
    }

    static func persist(frame: NSRect, on screen: NSScreen) {
        let area = workArea(on: screen)
        UserDefaults.standard.set(
            [frame.origin.x - area.origin.x, frame.origin.y - area.origin.y],
            forKey: offsetKey
        )
    }

    static func resetPosition() {
        UserDefaults.standard.removeObject(forKey: offsetKey)
    }

    private static func savedOffset() -> CGPoint? {
        guard let stored = UserDefaults.standard.array(forKey: offsetKey) as? [Double],
              stored.count == 2
        else { return nil }
        return CGPoint(x: stored[0], y: stored[1])
    }

    private static func clamp(_ rect: NSRect, to area: NSRect) -> NSRect {
        var result = rect
        result.origin.x = min(max(rect.origin.x, area.minX), area.maxX - rect.width)
        result.origin.y = min(max(rect.origin.y, area.minY), area.maxY - rect.height)
        return result
    }
}
