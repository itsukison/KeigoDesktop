import AppKit
import ApplicationServices

/// Whether the Dock is *actually* occupying the bottom of a screen right now.
///
/// **`NSScreen.visibleFrame` cannot answer this, and that is not a subtlety.**
/// Measured on a 1920×1080 display while a full-screen space had the Dock hidden:
/// the Dock's own AX element reported its top edge at y = 1080 — the screen's bottom,
/// i.e. gone — while `visibleFrame` still reserved 78 pt for it (`minY = 78`).
/// `didChangeScreenParameters` does not fire for this, and neither does polling
/// `visibleFrame`, because the value never changes.
///
/// So anchoring to `visibleFrame` alone strands the bar 78 pt above the bottom of
/// every full-screen app. The Dock knows where it is; ask it.
enum DockProbe {

    private static var cachedList: AXUIElement?

    /// True when a bottom-oriented Dock is on screen and overlapping `screen`.
    static func occupiesBottom(of screen: NSScreen) -> Bool {
        guard let dock = dockFrame() else { return false }
        // A left- or right-hand Dock is taller than it is wide and takes nothing off
        // the bottom edge.
        guard dock.width > dock.height else { return false }
        // Multi-display: the Dock lives on one screen at a time.
        guard dock.maxX > screen.frame.minX, dock.minX < screen.frame.maxX else { return false }
        // Hidden Docks park at or below the bottom edge rather than disappearing.
        return dock.maxY > screen.frame.minY
    }

    private static func dockFrame() -> CGRect? {
        if let cachedList, let frame = frame(of: cachedList) { return frame }
        cachedList = resolveDockList()
        guard let cachedList else { return nil }
        return frame(of: cachedList)
    }

    private static func resolveDockList() -> AXUIElement? {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        else { return nil }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
                == .success,
              let list = (children as? [AXUIElement])?.first
        else { return nil }

        AXUIElementSetMessagingTimeout(list, 0.2)
        return list
    }

    /// AX reports a top-left origin with y growing downward, relative to the primary
    /// screen's top edge. AppKit is the other way up.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
                == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
                == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: position.x,
            y: primaryTop - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}
