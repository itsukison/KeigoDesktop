#if DEBUG
import AppKit
import ScreenCaptureKit
import DesktopRewriteKit
import TextIO

struct VisualIntentCapture {
    let snapshot: VisualComposerSnapshot
    let request: VisualIntentRequest
    let originalPNG: Data
    let markedPNG: Data
    let windowID: CGWindowID
    let captureMs: Int
    let pixelScale: Float
    let focusSubscriptions: Int
    let frameMetadata: [String: String]

    @MainActor
    static func take(ax: AXTextIO, pid: pid_t, epochIsValid: () -> Bool) async throws -> Self {
        let start = Date()
        guard CGPreflightScreenCaptureAccess() else { throw VisualCaptureError.screenPermission }
        let focus = VisualFocusWatch()
        focus.watch(pid: pid)
        defer { focus.stop() }
        let snapshot = try await ax.freezeVisualComposer(frontmostPID: pid)
        if let helperPID = snapshot.target.element?.pid, helperPID != pid { focus.watch(pid: helperPID) }
        func checkEpoch() throws {
            guard focus.changes == 0, epochIsValid(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw VisualCaptureError.staleTarget
            }
        }
        try checkEpoch()
        let inventory = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = inventory.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0
                && VisualCaptureGeometry.agrees($0.frame, snapshot.windowFrame)
                && $0.frame.contains(snapshot.composerFrame)
        }
        let titled = candidates.filter { $0.title == snapshot.windowTitle && !snapshot.windowTitle.isEmpty }
        let matches = candidates.count == 1 ? candidates : titled
        guard matches.count == 1, let window = matches.first else { throw VisualCaptureError.ambiguousWindow }
        try checkEpoch()
        try await ax.validateVisualComposer(snapshot)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // Fail visibly if this OS/window supplies a different content size. Do not
        // silently assume the titlebar or a shadow inset is absent from the mapping.
        guard abs(filter.contentRect.width - window.frame.width) <= 2,
              abs(filter.contentRect.height - window.frame.height) <= 2 else { throw VisualCaptureError.unreadableGeometry }
        let config = VisualWindowFrame.configuration(for: filter)
        guard config.width > 0, config.height > 0, config.width * config.height <= 32_000_000 else {
            throw VisualCaptureError.imageEncoding
        }
        let frame = try await VisualWindowFrame().capture(filter: filter, config: config)
        let image = frame.image
        var frameMetadata = frame.diagnostics
        frameMetadata["filterContentRect"] = NSStringFromRect(filter.contentRect)
        frameMetadata["windowFrame"] = NSStringFromRect(window.frame)
        try checkEpoch()
        try await ax.validateVisualComposer(snapshot)
        try checkEpoch()
        guard let screenRect = frame.rect(.screenRect), let contentRect = frame.rect(.contentRect),
              let contentScale = (frame.info[.contentScale] as? NSNumber)?.doubleValue,
              let scaleFactor = (frame.info[.scaleFactor] as? NSNumber)?.doubleValue,
              let box = VisualCaptureGeometry.frameImageBox(composer: snapshot.composerFrame, window: window.frame,
                  screenRect: screenRect, contentRect: contentRect, contentScale: contentScale, scaleFactor: scaleFactor,
                  width: image.width, height: image.height) else {
            throw VisualCaptureError.unreadableGeometry
        }
        frameMetadata["geometryVersion"] = "single-window-frame-v2"
        frameMetadata["composerImageRect"] = NSStringFromRect(box.rect)
        frameMetadata["childWindowsIncluded"] = "false on macOS 14.2+; frame extent verified on all versions"
        let original = NSBitmapImageRep(cgImage: image)
        guard let originalPNG = original.representation(using: .png, properties: [:]),
              let marked = mark(image, composer: box),
              let markedPNG = marked.representation(using: .png, properties: [:]),
              let jpeg = marked.representation(using: .jpeg, properties: [.compressionFactor: 0.9]),
              jpeg.count <= 8_000_000 else { throw VisualCaptureError.imageEncoding }
        let request = VisualIntentRequest(captureId: UUID().uuidString, targetId: UUID().uuidString,
            intent: snapshot.target.text, appBundleId: snapshot.target.hostAppBundleId ?? "unknown",
            imageWidth: image.width, imageHeight: image.height, composerBox: box, imageBase64: jpeg.base64EncodedString())
        return Self(snapshot: snapshot, request: request, originalPNG: originalPNG, markedPNG: markedPNG,
                    windowID: window.windowID, captureMs: Int(Date().timeIntervalSince(start) * 1000),
                    pixelScale: filter.pointPixelScale, focusSubscriptions: focus.subscriptions, frameMetadata: frameMetadata)
    }

    private static func mark(_ image: CGImage, composer: ImageBox) -> NSBitmapImageRep? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let r = CGRect(x: composer.x, y: Double(image.height) - composer.y - composer.height,
                       width: composer.width, height: composer.height)
        context.setStrokeColor(NSColor.magenta.cgColor)
        context.setLineWidth(3)
        context.stroke(r.insetBy(dx: 1.5, dy: 1.5))
        // Numeric metadata and the unique magenta outline identify the target;
        // no opaque label is drawn over source text.
        guard let marked = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: marked)
    }
}
#endif
