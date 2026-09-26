// Offline asset preparation, not part of the app target.
// Compile with swiftc -O. Pass the white-background master MP4; stdout is 960×960
// BGRA at the master's 24 fps, ready for ffmpeg's HEVC-with-alpha encoder.
import AVFoundation
import Foundation

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let track = try await asset.loadTracks(withMediaType: .video)[0]
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
output.alwaysCopiesSampleData = false
reader.add(output)
guard reader.startReading() else { fatalError("Cannot read mascot master") }
var frameCount = 0
while let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    precondition(width == 960 && height == 960, "Update the encoder dimensions for a new master")
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let source = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        pixels.withUnsafeMutableBytes { destination in
            destination.baseAddress!.advanced(by: y * width * 4)
                .copyMemory(from: source.advanced(by: y * stride), byteCount: width * 4)
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

    // The mascot has a closed black outline. Flood only the outside, stopping at
    // that outline; an ordinary white colorkey also removes face/eye antialiasing.
    var visited = [Bool](repeating: false, count: width * height)
    var queue = [Int]()
    queue.reserveCapacity(width * height)
    func enqueue(_ index: Int) {
        guard !visited[index] else { return }
        visited[index] = true
        let offset = index * 4
        if min(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 16 {
            queue.append(index)
        }
    }
    for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
    for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
    var head = 0
    while head < queue.count {
        let index = queue[head]
        head += 1
        let x = index % width, y = index / width
        if x > 0 { enqueue(index - 1) }
        if x + 1 < width { enqueue(index + 1) }
        if y > 0 { enqueue(index - width) }
        if y + 1 < height { enqueue(index + width) }
    }
    // Unmatte the exterior antialiasing against its original white field. Those
    // partially covered pixels belong to the black outline, not a white fringe.
    for index in queue {
        let offset = index * 4
        let light = Int(min(pixels[offset], pixels[offset + 1], pixels[offset + 2]))
        pixels[offset + 3] = UInt8(max(0, min(255, (250 - light) * 255 / 234)))
        pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0
    }
    precondition(pixels[((height / 2) * width + width / 2) * 4 + 3] == 255,
                 "Exterior matte leaked through the mascot outline")
    try FileHandle.standardOutput.write(contentsOf: Data(pixels))
    frameCount += 1
}
guard reader.status == .completed else { fatalError("Incomplete mascot decode: \(String(describing: reader.error))") }
FileHandle.standardError.write(Data("Prepared \(frameCount) frames\n".utf8))
