#if DEBUG
import AppKit
import ApplicationServices

@MainActor
final class VisualFocusWatch {
    private var observers: [AXObserver] = []
    private(set) var changes = 0
    private(set) var subscriptions = 0

    func watch(pid: pid_t) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<VisualFocusWatch>.fromOpaque(context).takeUnretainedValue().changes += 1
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            if AXObserverAddNotification(observer, app, name as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success { subscriptions += 1 }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers.append(observer)
    }

    func stop() {
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }
}
#endif
