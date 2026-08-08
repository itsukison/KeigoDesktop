import AppKit
import SwiftUI

/// The window's marks and plates.
///
/// These used to exist to *quarantine* colour: the old system forbade its two accents
/// on buttons, links, badges and focus rings, so every coloured pixel in the window
/// had to be artwork and every piece of artwork had to live in this file. `design.md`
/// puts the accent on the chrome itself, so nothing here is load-bearing any more —
/// it is just the handful of shapes the window draws that are not text or a control.

/// The product mark: the keycap, as line art, in the accent.
///
/// The window gets the outline cut rather than the full-colour app icon. The icon is a
/// two-tone illustration with a black keyline, and at 15 pt on a `#f5f6f7` sidebar it
/// reads as a photograph of something rather than as chrome. Line art in `#5a57ba` is
/// the same rule the rest of §14 follows — the accent is on the chrome. The overlay,
/// which is dark and cannot tint a keyline away, takes the colour cut instead
/// (`BrandGlyph`).
struct AppMark: View {
    var size: CGFloat = 15

    var body: some View {
        Icon(.mark, size: size)
            .foregroundStyle(Tokens.Window.accent)
    }
}

/// The product mark in full colour — an off-white keycap with black eyes.
///
/// This is the one image in the app that is not a template. On the overlay's `#141312`
/// the outline cut collapses into a smudge at 16 pt (the keycap's own double keyline
/// closes up), while the filled art is a white shape with two dark counters and stays
/// legible down to 16 pt at 1x. It is still achromatic, so §8's "the generating capsule
/// is the only colour in the overlay" survives.
struct BrandGlyph: View {
    var size: CGFloat = 16

    var body: some View {
        Image(Icon.Name.markFilled)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Identity, in the sidebar and on the account page. A flat accent disc with the
/// initial knocked out in white.
struct Avatar: View {
    let initial: String
    var diameter: CGFloat = 30

    var body: some View {
        Circle()
            .fill(Tokens.Window.accent)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(initial)
                    .font(Tokens.Font.body(diameter * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A glyph on a tinted disc — `design.md`'s app-integration plates, and what an
/// empty state leads with here.
struct IconPlate: View {
    let icon: Icon.Name
    var diameter: CGFloat = 36
    var tinted = true

    var body: some View {
        Circle()
            .fill(tinted ? Tokens.Window.accentTint : Tokens.Window.surface)
            .frame(width: diameter, height: diameter)
            .overlay(
                Icon(icon, size: diameter * 0.46)
                    .foregroundStyle(tinted ? Tokens.Window.accent : Tokens.Window.textSecondary)
            )
    }
}

/// A real application icon, by bundle id.
///
/// `design.md`'s home page leads with the icons of the apps you dictate into; ours
/// shows the apps you have actually rewritten in, which is the same claim backed by
/// the local history. Falls back to a plate for an app that has since been removed.
struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 22

    var body: some View {
        if let icon = Self.icon(for: bundleId) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            IconPlate(icon: .window, diameter: size, tinted: false)
        }
    }

    private static var cache: [String: NSImage?] = [:]

    private static func icon(for bundleId: String) -> NSImage? {
        if let cached = cache[bundleId] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleId] = icon
        return icon
    }
}

/// The drag affordance: six dots, the shape everyone already reads as "grab me".
/// SF Symbols has no 2×3 grip, so it is drawn.
struct GripHandle: View {
    var active = false

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(active ? Tokens.Window.textSecondary : Tokens.Window.textTertiary)
                            .frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        // Bigger than it draws. Six 2.5 pt dots is a 14 pt target, which is a miss
        // waiting to happen on a row you are meant to grab.
        .frame(width: 26, height: 40)
        .contentShape(Rectangle())
    }
}
