import AppKit
import DesktopRewriteKit
import SwiftUI

/// A plain titled window, not an `NSPanel` — this one is allowed to be key and main.
///
/// **Closing it must not touch the overlay and must not quit the app.** The pill is
/// owned by `AppDelegate`, not by this window, and `isReleasedWhenClosed = false`
/// keeps the instance alive so reopening from the menu bar returns to the same page
/// rather than rebuilding from scratch. The only way out of the app is 終了.
final class MainWindowController: NSWindowController {

    convenience init(model: MainModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = tr("敬語ボタン", "KeigoButton", "敬語ボタン")
        // The sidebar runs to the top edge behind the traffic lights, as in all three
        // references. `MainWindowView` reserves the 36 pt they need.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The shell colour, not the canvas: the content is a panel floating inside
        // the window, and this is what shows in the margin around it.
        window.backgroundColor = NSColor(Tokens.Window.shell)
        // The window's palette is a fixed light one. Without this, a Mac in dark mode
        // draws the system-supplied halves — switches, text-field carets, the
        // titlebar — from a dark appearance against light-only surfaces.
        window.appearance = NSAppearance(named: .aqua)
        // Wide enough for the 780 pt preferences card to sit inside with a margin.
        window.contentMinSize = NSSize(width: 920, height: 640)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainWindowView(model: model))
        window.center()
        self.init(window: window)
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        // `.accessory` apps are not brought forward by `makeKeyAndOrderFront` alone —
        // without this the window opens behind whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// On screen, in front, and **without taking the keyboard**.
    ///
    /// For every other caller `present()` is right: the user asked for this window, so
    /// they want to be in it. The update notice is the one caller that nobody asked for
    /// — the app decided on its own that now was the moment — and `NSApp.activate` there
    /// takes focus out of whatever the user is typing in. That is precisely what §4
    /// exists to prevent everywhere else in this app, and Sparkle's own scheduled alert
    /// was declined for the same reason.
    ///
    /// `orderFrontRegardless` is what makes this work for an `.accessory` process:
    /// `orderFront` is ignored while the app is inactive, and `makeKeyAndOrderFront`
    /// would take the focus this method exists to leave alone. The window arrives above
    /// the user's other windows, keeps their insertion point where it was, and becomes
    /// key the moment they click it.
    func presentWithoutActivating() {
        window?.orderFrontRegardless()
    }
}
