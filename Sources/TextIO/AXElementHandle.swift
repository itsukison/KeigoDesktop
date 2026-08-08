import ApplicationServices
import Foundation

/// A `Sendable` box around `AXUIElement`.
///
/// `AXUIElement` is a CF type and thread-safe to retain, but it is not marked
/// `Sendable`, and every call on it is synchronous IPC into another process. This
/// wrapper exists so a captured target can cross the queue boundary between the
/// AX serial queue and the main actor without `@unchecked` leaking into call sites.
public struct AXElementHandle: @unchecked Sendable {
    public let element: AXUIElement
    /// The owning process. Cached so the Electron workaround can be applied once
    /// per pid rather than per call.
    public let pid: pid_t

    init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
    }
}

extension AXUIElement {
    /// §5, non-negotiable: every element we touch gets a messaging timeout.
    ///
    /// AX calls are synchronous IPC. Without this, one beachballing app blocks our
    /// thread and the pill freezes with it — the failure mode is not "this app
    /// doesn't work", it is "the whole product is hung".
    func applyMessagingTimeout(_ seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(self, seconds)
    }

    func copyAttribute(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func stringAttribute(_ attribute: String) -> String? {
        copyAttribute(attribute) as? String
    }

    func boolAttribute(_ attribute: String) -> Bool? {
        copyAttribute(attribute) as? Bool
    }

    func rangeAttribute(_ attribute: String) -> CFRange? {
        guard let value = copyAttribute(attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    func elementAttribute(_ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    @discardableResult
    func setAttribute(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    var isSettable: Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            self, kAXSelectedTextAttribute as CFString, &settable
        ) == .success else {
            return false
        }
        return settable.boolValue
    }

    var processIdentifier: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }
}
