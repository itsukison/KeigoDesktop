import AppKit
import TextIO

/// The AppKit halves of `TextIO`'s two protocols. They live here rather than in
/// `Sources/` so that package stays AppKit-free and unit-testable (§3).

struct SystemPasteboard: PasteboardBridge {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func write(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func clear() {
        NSPasteboard.general.clearContents()
    }
}

struct RunningAppActivator: AppActivator {
    func activate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [])
    }
}

extension NSWorkspace {
    /// Snapshotted before capture (§4 step 2) so the clipboard write path knows which
    /// app to reactivate.
    var frontmostPID: pid_t? {
        frontmostApplication?.processIdentifier
    }
}
