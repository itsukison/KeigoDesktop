#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-dmg-background.swift input.svg output.png\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let scale = 1
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

bitmap.size = outputSize
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("could not create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
image.draw(
    in: NSRect(origin: .zero, size: outputSize),
    from: NSRect(origin: .zero, size: image.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not encode PNG\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: .atomic)
