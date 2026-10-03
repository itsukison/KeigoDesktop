import Foundation

public struct ImageBox: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(_ rect: CGRect) {
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public func fits(width: Int, height: Int) -> Bool {
        [x, y, self.width, self.height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && self.width > 0 && self.height > 0
            && x + self.width <= Double(width) && y + self.height <= Double(height)
    }
    public func overlaps(_ other: ImageBox) -> Bool {
        x < other.x + other.width && other.x < x + width
            && y < other.y + other.height && other.y < y + height
    }
}

public enum VisualCaptureGeometry {
    public static func agrees(_ a: CGRect, _ b: CGRect, tolerance: Double = 2) -> Bool {
        [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height]
            .allSatisfy { $0.isFinite && abs($0) <= tolerance }
    }
    /// SCStream contentRect is in surface points; scaleFactor converts it to
    /// pixels. contentScale describes scaling from the single source window.
    /// Reject a child-window union or any other unexplained backing extent.
    public static func frameImageBox(composer: CGRect, window: CGRect, screenRect: CGRect,
                                     contentRect: CGRect, contentScale: Double, scaleFactor: Double,
                                     width: Int, height: Int) -> ImageBox? {
        guard agrees(window, screenRect), window.contains(composer),
              contentScale.isFinite, contentScale > 0, scaleFactor.isFinite, scaleFactor > 0,
              width > 0, height > 0,
              [window.minX, window.minY, window.width, window.height, composer.minX, composer.minY,
               composer.width, composer.height, contentRect.minX, contentRect.minY, contentRect.width,
               contentRect.height].allSatisfy(\.isFinite),
              window.width > 0, window.height > 0, composer.width > 0, composer.height > 0,
              contentRect.width > 0, contentRect.height > 0 else { return nil }
        let scale = contentScale * scaleFactor
        let pixels = CGRect(x: contentRect.minX * scaleFactor, y: contentRect.minY * scaleFactor,
                            width: contentRect.width * scaleFactor, height: contentRect.height * scaleFactor)
        guard abs(pixels.width - window.width * scale) <= 2,
              abs(pixels.height - window.height * scale) <= 2,
              pixels.minX >= -0.5, pixels.minY >= -0.5,
              pixels.maxX <= Double(width) + 0.5, pixels.maxY <= Double(height) + 0.5 else { return nil }
        let mapped = CGRect(x: pixels.minX + (composer.minX - window.minX) * scale,
                            y: pixels.minY + (composer.minY - window.minY) * scale,
                            width: composer.width * scale, height: composer.height * scale)
        // Only absorb sub-pixel rounding at a surface boundary, never crop a
        // genuinely clipped composer into an apparently valid rectangle.
        let surface = CGRect(x: 0, y: 0, width: width, height: height)
        guard surface.insetBy(dx: -0.5, dy: -0.5).contains(mapped) else { return nil }
        let box = ImageBox(mapped.intersection(surface))
        return box.fits(width: width, height: height) ? box : nil
    }
    /// AX and SCWindow use global top-left points. The screenshot has no shadows
    /// and fills its output. Use frameImageBox for captured frames with metadata.
    public static func imageBox(composer: CGRect, window: CGRect, width: Int, height: Int) -> ImageBox? {
        guard width > 0, height > 0, window.width > 0, window.height > 0,
              window.contains(composer), composer.width > 0, composer.height > 0 else { return nil }
        let box = ImageBox(CGRect(x: (composer.minX - window.minX) * Double(width) / window.width,
                                 y: (composer.minY - window.minY) * Double(height) / window.height,
                                 width: composer.width * Double(width) / window.width,
                                 height: composer.height * Double(height) / window.height))
        return box.fits(width: width, height: height) ? box : nil
    }
}

public struct VisualIntentRequest: Codable, Sendable {
    public let captureId: String
    public let targetId: String
    public let intent: String
    public let appBundleId: String
    public let imageWidth: Int
    public let imageHeight: Int
    public let composerBox: ImageBox
    public let imageBase64: String
    public init(captureId: String, targetId: String, intent: String, appBundleId: String,
                imageWidth: Int, imageHeight: Int, composerBox: ImageBox, imageBase64: String) {
        self.captureId = captureId; self.targetId = targetId; self.intent = intent
        self.appBundleId = appBundleId; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.composerBox = composerBox; self.imageBase64 = imageBase64
    }
    public func validate() throws {
        let safeID: (String) -> Bool = { value in
            !value.isEmpty && value.utf8.count <= 80
                && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || $0 == 45 || $0 == 95 }
        }
        guard safeID(captureId), safeID(targetId), !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              intent.utf16.count <= 16000, (1...16000).contains(imageWidth), (1...16000).contains(imageHeight),
              imageWidth * imageHeight <= 32_000_000, composerBox.fits(width: imageWidth, height: imageHeight),
              imageBase64.utf8.count <= 10_666_668, let image = Data(base64Encoded: imageBase64),
              image.prefix(3) == Data([0xff, 0xd8, 0xff]) else { throw RewriteError.invalidResponse }
    }
}

public struct VisualIntentResult: Codable, Sendable {
    public struct Region: Codable, Sendable {
        public let label: String
        public let box: ImageBox
    }
    public struct Evidence: Codable, Sendable {
        public let excerpt: String
        public let box: ImageBox
        public let author: String?
        public let partial: Bool
    }
    public enum Status: String, Codable, Sendable {
        case ready, ambiguousTarget = "ambiguous_target", insufficientContext = "insufficient_context"
    }
    public let captureId: String
    public let targetId: String
    public let status: Status
    public let conversationRegion: [Region]
    public let evidence: [Evidence]
    public let missingContext: [String]
    public let draft: String?

    public func validate(for request: VisualIntentRequest) throws {
        guard captureId == request.captureId, targetId == request.targetId,
              conversationRegion.count <= 8, evidence.count <= 16,
              conversationRegion.allSatisfy({ $0.box.fits(width: request.imageWidth, height: request.imageHeight) }),
              evidence.allSatisfy({ !$0.excerpt.isEmpty && $0.box.fits(width: request.imageWidth, height: request.imageHeight) }),
              status == .ready ? (!(draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !conversationRegion.isEmpty && !evidence.isEmpty && missingContext.isEmpty) : draft == nil
        else { throw RewriteError.invalidResponse }
    }
}

public struct VisualIntentResponse: Codable, Sendable {
    public let result: VisualIntentResult
    public let model: String
    public let reasoningEffort: String?
    public let promptVersion: String
    public let modelMs: Int
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let validationVersion: String?
    public let geometryWarnings: [String]?
}
