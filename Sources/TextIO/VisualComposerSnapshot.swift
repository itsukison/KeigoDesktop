import ApplicationServices
import DesktopRewriteKit
import Foundation

public struct VisualComposerSnapshot: Sendable {
    public let target: TextTarget
    public let window: AXElementHandle
    public let applicationPID: pid_t
    public let composerFrame: CGRect
    public let windowFrame: CGRect
    public let windowTitle: String
    public let capturedAt: Date
}

public enum VisualCaptureError: String, Error, LocalizedError {
    case unsupportedComposer, unreadableGeometry, staleTarget, ambiguousWindow, screenPermission, imageEncoding
    public var errorDescription: String? {
        switch self {
        case .unsupportedComposer: return "Focus a message body containing your rough intention. Search, secure, empty and unreadable fields are unsupported."
        case .unreadableGeometry: return "The focused field or window has no usable geometry."
        case .staleTarget: return "The field, text or window changed during capture. Keep the target focused and try again."
        case .ambiguousWindow: return "The focused field could not be matched to exactly one capture window."
        case .screenPermission: return "Enable Screen Recording in setup, then start a fresh capture."
        case .imageEncoding: return "The captured image could not be encoded or mapped."
        }
    }
}

extension AXTextIO {
    public func freezeVisualComposer(frontmostPID: pid_t) throws -> VisualComposerSnapshot {
        let started = Date()
        let anchor = try captureReplyAnchor(frontmostPID: frontmostPID)
        guard let field = anchor.target.element, let window = anchor.root,
              anchor.draftStatus == .present,
              anchor.target.text.count <= 8000,
              field.element.stringAttribute(kAXSubroleAttribute) != "AXSearchField",
              field.element.stringAttribute(kAXRoleAttribute) != "AXSearchField" else {
            throw VisualCaptureError.unsupportedComposer
        }
        guard let composerFrame = visualFrame(field.element), let windowFrame = visualFrame(window.element),
              windowFrame.contains(composerFrame) else { throw VisualCaptureError.unreadableGeometry }
        return VisualComposerSnapshot(target: anchor.target, window: window, applicationPID: frontmostPID,
            composerFrame: composerFrame, windowFrame: windowFrame,
            windowTitle: window.element.stringAttribute(kAXTitleAttribute) ?? "", capturedAt: started)
    }

    public func validateVisualComposer(_ snapshot: VisualComposerSnapshot) throws {
        let current = try freezeVisualComposer(frontmostPID: snapshot.applicationPID)
        guard let original = snapshot.target.element, let focused = current.target.element,
              CFEqual(original.element, focused.element), CFEqual(snapshot.window.element, current.window.element),
              snapshot.target.text == current.target.text, snapshot.windowTitle == current.windowTitle,
              VisualCaptureGeometry.agrees(snapshot.composerFrame, current.composerFrame, tolerance: 0.5),
              VisualCaptureGeometry.agrees(snapshot.windowFrame, current.windowFrame, tolerance: 0.5) else {
            throw VisualCaptureError.staleTarget
        }
    }

    private func visualFrame(_ element: AXUIElement) -> CGRect? {
        element.applyMessagingTimeout()
        guard let p = element.copyAttribute(kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = element.copyAttribute(kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
}
