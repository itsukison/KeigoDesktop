import AppKit
import Foundation

// Offline evaluation preparation only. No capture, credentials, or app changes.
// Crops and pane swaps do not rescale or generate content. Derived images are
// re-encoded as lossy JPEGs at quality 0.9, matching the prototype's encoder.
let args = CommandLine.arguments
guard args.count == 5 else { fatalError("usage: script OUTPUT LEFT_REQUEST RIGHT_REQUEST EXPORTED_CAPTURE_FOLDER") }
let root = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
typealias Object = [String: Any]
func read(_ path: String) throws -> Object { try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! Object }
func image(_ request: Object) -> CGImage {
    NSBitmapImageRep(data: Data(base64Encoded: request["imageBase64"] as! String)!)!.cgImage!
}
func encode(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])! }
func rect(_ box: Object) -> CGRect { CGRect(x: box["x"] as! Double, y: box["y"] as! Double, width: box["width"] as! Double, height: box["height"] as! Double) }
func box(_ r: CGRect) -> Object { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func swap(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height, half = w / 2
    let c = context(w, h)
    c.draw(image.cropping(to: CGRect(x: half, y: 0, width: half, height: h))!, in: CGRect(x: 0, y: 0, width: half, height: h))
    c.draw(image.cropping(to: CGRect(x: 0, y: 0, width: half, height: h))!, in: CGRect(x: half, y: 0, width: half, height: h))
    return c.makeImage()!
}
func mark(_ image: CGImage, _ target: CGRect) -> CGImage {
    let c = context(image.width, image.height)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    c.setStrokeColor(NSColor.magenta.cgColor); c.setLineWidth(3)
    c.stroke(CGRect(x: target.minX, y: CGFloat(image.height) - target.maxY, width: target.width, height: target.height).insetBy(dx: 1.5, dy: 1.5))
    return c.makeImage()!
}
var cases: [Object] = []
func save(_ name: String, request source: Object, pixels: CGImage? = nil, target: CGRect? = nil,
          crop: CGRect? = nil, expected: String, family: String, variant: String, provenance: String) throws {
    var r = source
    var img = pixels ?? image(source)
    var composer = target ?? rect(source["composerBox"] as! Object)
    if let crop {
        precondition(crop.contains(composer))
        img = img.cropping(to: crop)!
        composer = composer.offsetBy(dx: -crop.minX, dy: -crop.minY)
    }
    // Exact source requests stay byte-for-byte intact in the raw condition.
    if pixels != nil || target != nil || crop != nil {
        r["captureId"] = UUID().uuidString
        r["imageBase64"] = encode(img).base64EncodedString()
        r["imageWidth"] = img.width; r["imageHeight"] = img.height
        r["composerBox"] = box(composer)
    }
    let folder = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]).write(to: folder.appendingPathComponent("request.json"))
    try Data(base64Encoded: r["imageBase64"] as! String)!.write(to: folder.appendingPathComponent("input.jpg"))
    var entry: Object = ["case": name, "family": family, "variant": variant, "expected": expected,
                         "provenance": provenance, "request": folder.appendingPathComponent("request.json").path,
                         "composerBox": box(composer), "width": img.width, "height": img.height]
    if let crop { entry["oracleCrop"] = box(crop) }
    cases.append(entry)
}
for (path, topic) in [(args[2], "Cedar"), (args[3], "Indigo")] {
    var r = try read(path)
    // Opaque IDs cannot contradict a swapped image or leak left/right labels.
    r["captureId"] = UUID().uuidString; r["targetId"] = UUID().uuidString
    let original = image(r), composer = rect(r["composerBox"] as! Object)
    for swapped in [false, true] {
        let target = swapped ? composer.offsetBy(dx: composer.minX < 600 ? 600 : -600, dy: 0) : composer
        let side = target.minX < 600 ? "left" : "right"
        let name = "render-\(swapped ? "swapped" : "original")-\(side)"
        let img: CGImage? = swapped ? swap(original) : nil
        for cropped in [false, true] {
            try save(name + (cropped ? "-crop" : "-full"), request: r, pixels: img,
                     target: swapped ? target : nil,
                     crop: cropped ? CGRect(x: side == "left" ? 0 : 600, y: 0, width: 600, height: 800) : nil,
                     expected: topic, family: "render", variant: cropped ? "crop" : "full",
                     provenance: "Existing synthetic JPEG; entire 600-pixel columns swapped when indicated. No new native capture.")
        }
    }
}
let exported = URL(fileURLWithPath: args[4], isDirectory: true)
let browser = try read(exported.appendingPathComponent("request.json").path)
let original = NSBitmapImageRep(data: try Data(contentsOf: exported.appendingPathComponent("original.png")))!.cgImage!
// Manually measured in the exported source PNG, not AX or a model prediction.
let corrected = CGRect(x: 37, y: 700, width: 787, height: 96)
let marked = mark(original, corrected)
try save("browser-raw", request: browser, expected: "Cedar", family: "browser", variant: "raw", provenance: "Exact exported request including misaligned marker and metadata.")
try save("browser-corrected-full", request: browser, pixels: marked, target: corrected,
         expected: "Cedar", family: "browser", variant: "corrected-full", provenance: "Exported original.png with manually aligned composer marker; same intent and app metadata.")
try save("browser-corrected-crop", request: browser, pixels: marked, target: corrected,
         crop: CGRect(x: 18, y: 177, width: 826, height: 638), expected: "Cedar", family: "browser", variant: "corrected-crop",
         provenance: "Human-selected left conversation pane from corrected PNG; excludes browser chrome, other pane and answer-key footer.")
try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("manifest.json"))
print("Prepared \(cases.count) conditions in \(root.path)")
