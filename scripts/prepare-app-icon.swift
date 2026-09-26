// Run from the repository root: swift scripts/prepare-app-icon.swift
// Package generated full-bleed artwork on the existing macOS icon grid.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let artwork = NSImage(contentsOf: root.appendingPathComponent("public/generated/keigo-icon-cyan-v2.png"))!
let catalog = root.appendingPathComponent("App/Resources/Icons.xcassets")

func export(size: Int, masked: Bool, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let width = CGFloat(size)
    let inset = masked ? width * 100 / 1024 : 0
    let bounds = CGRect(x: inset, y: inset, width: width - 2 * inset, height: width - 2 * inset)
    if masked {
        let path = NSBezierPath()
        for step in 0...1024 {
            let angle = CGFloat(step) / 1024 * 2 * .pi
            let x = cos(angle), y = sin(angle)
            let point = CGPoint(x: bounds.midX + (x < 0 ? -1 : 1) * pow(abs(x), 0.4) * bounds.width / 2,
                                y: bounds.midY + (y < 0 ? -1 : 1) * pow(abs(y), 0.4) * bounds.height / 2)
            if step == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        path.addClip()
    }
    artwork.draw(in: bounds)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

func writeSet(name: String, icon: Bool) throws {
    let directory = catalog.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for points in (icon ? [16, 32, 128, 256, 512] : [64]) {
        for scale in [1, 2] {
            let filename = "cyan-\(points)@\(scale)x.png"
            try export(size: points * scale, masked: icon, to: directory.appendingPathComponent(filename))
            var entry = ["filename": filename, "idiom": icon ? "mac" : "universal", "scale": "\(scale)x"]
            if icon { entry["size"] = "\(points)x\(points)" }
            images.append(entry)
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("Contents.json"))
}
try writeSet(name: "KeigoAppIcon.appiconset", icon: true)
try writeSet(name: "KeigoAppMark.imageset", icon: false)

// Legacy catalog names are blue aliases too: no bundled fallback may show purple.
for (legacy, current) in [("AppIcon.appiconset", "KeigoAppIcon.appiconset"),
                          ("icon-brand.imageset", "KeigoAppMark.imageset")] {
    let directory = catalog.appendingPathComponent(legacy)
    let data = try Data(contentsOf: directory.appendingPathComponent("Contents.json"))
    let entries = (try JSONSerialization.jsonObject(with: data) as! [String: Any])["images"] as! [[String: String]]
    for entry in entries {
        guard let filename = entry["filename"], let scale = entry["scale"] else { continue }
        let points = entry["size"]?.components(separatedBy: "x").first ?? "64"
        let source = catalog.appendingPathComponent(current).appendingPathComponent("cyan-\(points)@\(scale).png")
        try Data(contentsOf: source).write(to: directory.appendingPathComponent(filename))
    }
}
