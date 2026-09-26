#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-dmg-background.swift input.svg output.png\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let scale = 2
let outputSize = NSSize(width: 720 * scale, height: 440 * scale)

guard let image = NSImage(contentsOf: sourceURL) else {
    fputs("could not load SVG: \(sourceURL.path)\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(outputSize.width),
    pixelsHigh: Int(outputSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("could not allocate output bitmap\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: 720, height: 440)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("could not create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
image.draw(
    in: NSRect(x: 0, y: 0, width: 720, height: 440),
    from: NSRect(origin: .zero, size: image.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)
// A Finder background cannot resolve the viewing Mac's language. Keep the single
// shared download bilingual (English/Japanese); never bake in build-host locale.
func label(_ text: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: paragraph
    ]
    (text as NSString).draw(in: NSRect(x: 32, y: 440 - top - 26, width: 656, height: 26),
                           withAttributes: attributes)
}
let primary = NSColor(srgbRed: 17/255, green: 17/255, blue: 17/255, alpha: 1)
let secondary = NSColor(srgbRed: 96/255, green: 106/255, blue: 112/255, alpha: 1)
label("KeigoButton", top: 28, size: 26, weight: .semibold, color: primary)
label("アプリを右のフォルダへドラッグしてインストール", top: 84, size: 14, weight: .regular, color: secondary)
label("Drag the app to the folder on the right to install", top: 110, size: 14, weight: .regular, color: secondary)
label("コピー後、アプリケーションから開く", top: 365, size: 12, weight: .regular, color: secondary)
label("Once copied, open it from Applications", top: 391, size: 12, weight: .regular, color: secondary)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not encode PNG\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: .atomic)
