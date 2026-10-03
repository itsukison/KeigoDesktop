import AppKit
import Foundation

// Synthetic provider smoke test only. This does not test AX or ScreenCaptureKit.
let output = CommandLine.arguments.dropFirst().first ?? "/tmp/keigo-visual-fixture"
let folder = URL(fileURLWithPath: output, isDirectory: true)
let targetLeft = CommandLine.arguments.contains("--left")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let width = 1200, height = 800
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
func text(_ s: String, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, size: CGFloat = 22) {
    (s as NSString).draw(in: CGRect(x: x, y: CGFloat(height) - top - 180, width: w, height: 180),
        withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
}
func outline(_ rect: CGRect, color: NSColor) {
    color.setStroke(); let p = NSBezierPath(rect: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
    p.lineWidth = 3; p.stroke()
}
text("Channel · Delivery", 30, 20, 520, size: 28)
text("Thread · Workshop", 650, 20, 520, size: 28)
text("Mina: For the Cedar shipment, can you finish your part by Thursday at 14:20? The reference is CEDAR-482.", 30, 140, 520)
text("Ren: For the Indigo workshop, can you finish your part by Monday at 09:45? The reference is INDIGO-917.", 650, 140, 520)
text("Reply to channel", 30, 500, 520)
text("Reply to thread", 650, 500, 520)
let intent = "Agree, and mention their deadline and reference."
text(intent, 45, 590, 490, size: 20); text(intent, 665, 590, 490, size: 20)
outline(CGRect(x: 30, y: 575, width: 520, height: 155), color: targetLeft ? .magenta : .gray)
outline(CGRect(x: 650, y: 575, width: 520, height: 155), color: targetLeft ? .gray : .magenta)
NSGraphicsContext.restoreGraphicsState()
let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
try jpeg.write(to: folder.appendingPathComponent("fixture.jpg"))
let request: [String: Any] = ["captureId": targetLeft ? "synthetic-left-1" : "synthetic-right-1", "targetId": targetLeft ? "left" : "right", "intent": intent,
    "appBundleId": "synthetic.fixture", "imageWidth": width, "imageHeight": height,
    "composerBox": ["x": targetLeft ? 30 : 650, "y": 575, "width": 520, "height": 155], "imageBase64": jpeg.base64EncodedString()]
try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    .write(to: folder.appendingPathComponent("request.json"))
print(folder.path)
