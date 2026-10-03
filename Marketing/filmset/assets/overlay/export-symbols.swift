// Native SF Symbols, rendered at the sizes/weights used by the SwiftUI overlay.
// Run from laptop/: swift Marketing/filmset/assets/overlay/export-symbols.swift
import AppKit

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let symbols: [(String, CGFloat, NSFont.Weight, CGFloat)] = [
    ("pencil", 11, .medium, 24), ("xmark", 11, .medium, 24),
    ("chevron.left", 9, .semibold, 24), ("chevron.right", 9, .semibold, 24),
    ("arrowshape.turn.up.left", 11, .regular, 16),
    ("arrow.up.circle.fill", 17, .regular, 20),
    ("arrow.clockwise", 11, .medium, 28), ("doc.on.doc", 11, .medium, 28),
    ("hand.thumbsup", 11, .medium, 28), ("hand.thumbsdown", 11, .medium, 28),
    ("return", 10, .medium, 14), ("arrow.up", 8, .bold, 20),
]
for (name, points, weight, canvas) in symbols {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: points, weight: weight)),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas * 3),
            pixelsHigh: Int(canvas * 3), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: 3, y: 3)
    image.draw(in: NSRect(x: (canvas - image.size.width) / 2,
                         y: (canvas - image.size.height) / 2,
                         width: image.size.width, height: image.size.height))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent(name + ".png"))
}
