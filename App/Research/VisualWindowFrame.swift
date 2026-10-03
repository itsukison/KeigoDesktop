#if DEBUG
import AppKit
import ScreenCaptureKit
import VideoToolbox
import TextIO

/// One on-demand frame, with the geometry attachments that captureImage and
/// captureSampleBuffer omit on some macOS versions. No rolling capture or audio.
@MainActor
final class VisualWindowFrame: NSObject, SCStreamOutput {
    // An immutable image and an immutable snapshot of numeric/rectangle metadata.
    struct Frame: @unchecked Sendable {
        let image: CGImage
        let info: [SCStreamFrameInfo: Any]
        func rect(_ key: SCStreamFrameInfo) -> CGRect? {
            guard let dictionary = info[key] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }
        var diagnostics: [String: String] {
            var values: [String: String] = [:]
            for key in [SCStreamFrameInfo.contentRect, .screenRect, .boundingRect, .contentScale, .scaleFactor, .status] {
                if let v = info[key] { values[key.rawValue] = String(describing: v) }
            }
            return values
        }
    }
    private var pending: CheckedContinuation<Frame, Error>?
    private var timeout: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * Double(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * Double(filter.pointPixelScale)).rounded())
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        config.capturesAudio = false
        if #available(macOS 14.2, *) { config.includeChildWindows = false }
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true
        config.destinationRect = CGRect(x: 0, y: 0, width: config.width, height: config.height)
        config.queueDepth = 3
        return config
    }

    func capture(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> Frame {
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        let outcome: Result<Frame, Error>
        do {
            let frame: Frame = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    if Task.isCancelled { finish(.failure(CancellationError())); return }
                    timeout = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        finish(.failure(VisualCaptureError.unreadableGeometry))
                    }
                    startTask = Task { @MainActor in
                        do { try await stream.startCapture() }
                        catch { finish(.failure(error)) }
                    }
                }
            } onCancel: {
                Task { @MainActor in self.finish(.failure(CancellationError())) }
            }
            outcome = .success(frame)
        } catch { outcome = .failure(error) }
        timeout?.cancel(); timeout = nil
        await startTask?.value; startTask = nil
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
        return try outcome.get()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? NSNumber)?.intValue == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr,
              let image else {
            Task { @MainActor in self.finish(.failure(VisualCaptureError.imageEncoding)) }
            return
        }
        let frame = Frame(image: image, info: info)
        Task { @MainActor in self.finish(.success(frame)) }
    }

    private func finish(_ result: Result<Frame, Error>) {
        guard let continuation = pending else { return }
        pending = nil; timeout?.cancel()
        continuation.resume(with: result)
    }

    /// Debug-only instrumentation for an explicitly supplied window ID. Writes
    /// geometry and a local image; no model/network request and no host interaction.
    static func probe() async throws {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--visual-window-probe"), args.count > i + 1,
              let id = UInt32(args[i + 1]), let o = args.firstIndex(of: "--output"), args.count > o + 1,
              CGPreflightScreenCaptureAccess() else { throw VisualCaptureError.screenPermission }
        let inventory = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let window = inventory.windows.first(where: { $0.windowID == id }) else { throw VisualCaptureError.ambiguousWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = configuration(for: filter)
        let frame = try await VisualWindowFrame().capture(filter: filter, config: config)
        var metadata = frame.diagnostics
        metadata["windowFrame"] = NSStringFromRect(window.frame)
        metadata["filterContentRect"] = NSStringFromRect(filter.contentRect)
        let folder = URL(fileURLWithPath: args[o + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("geometry.json"))
        try NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("frame.png"))
        print("Saved window geometry to \(folder.path)")
    }
}
#endif
