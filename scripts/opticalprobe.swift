import AppKit
import CoreText

// Run: `swift scripts/opticalprobe.swift`
//
// §14 item 5 / §17. SwiftUI centres a `Text` by its LINE BOX. If the ink inside that
// box is not centred in it, a glyph centred in the same HStack is centred against
// nothing the eye can see. `opticalNudge` corrects for that, and it was measured on
// Japanese. This asks whether the same number is right for Latin and for 简体字.
//
// delta = (ink centre) − (line-box centre), both relative to the baseline.
// delta > 0 means the ink sits ABOVE the box centre, so a sibling glyph reads low and
// has to be nudged up by delta — which is what `opticalCentre()` does.
//
// **Read the DIFFERENCES between languages, not the absolute numbers.** The box here
// is the font's ascender+descender; SwiftUI centres by its own laid-out line box, and
// the two are offset by a constant (this probe reports ja ≈ −0.3 where §14's
// ImageRenderer measurement of the real thing reports +1.5). That offset is a
// property of the font and the layout, not of the string, so it cancels when two
// languages are compared at the same size and weight — which is the only question
// this file is fit to answer.

let context = CGContext(
    data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
)!

func delta(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributed = NSAttributedString(string: string, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let ink = CTLineGetImageBounds(line, context)

    // The line box SwiftUI lays out, in baseline-relative coordinates.
    let boxCentre = (font.ascender + font.descender) / 2
    let inkCentre = ink.midY
    return inkCentre - boxCentre
}

let samples: [(String, [String])] = [
    ("ja", ["ホーム", "ボタン", "アカウント", "履歴", "設定"]),
    ("en", ["Home", "Buttons", "Account", "History", "Settings"]),
    ("zh", ["主页", "按钮", "账户", "历史", "设置"]),
]

print("size weight  ja     en     zh")
for size in stride(from: CGFloat(11), through: 15, by: 1) {
    for weight in [NSFont.Weight.regular, .medium] {
        let label = weight == .regular ? "regular" : "medium "
        var row = String(format: "%4.0f ", Double(size)) + label
        for (_, strings) in samples {
            let values = strings.map { delta($0, size: size, weight: weight) }
            let mean = values.reduce(0, +) / CGFloat(values.count)
            row += String(format: " %6.2f", Double(mean))
        }
        print(row)
    }
}

print("")
print("per-string spread at 14 pt / medium:")
for (name, strings) in samples {
    let values = strings.map { delta($0, size: 14, weight: .medium) }
    let formatted = zip(strings, values).map { $0.0 + " " + String(format: "%.2f", Double($0.1)) }
    print("  \(name): \(formatted.joined(separator: "  "))")
}
