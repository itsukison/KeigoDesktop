import SwiftUI

/// Two ramps, per AGENTS.md §8.
///
/// `Window` implements the Aside light system in `design.md`. `Overlay` is the dark ramp the bar, the capsule and the result
/// card are drawn from; it is its own ramp, not a derivation of the light one.
enum Tokens {

    // MARK: - Aside light surfaces

    enum Window {
        static let environment = Color(hex: 0xedfaff)
        static let shell = environment
        static let sidebar = Color(hex: 0xeff1f2)
        static let sidebarGlassTint = Color(hex: 0xeff6fa).opacity(0.93)
        static let secondaryPanel = Color(hex: 0xf1f9fc)
        static let canvas = Color(hex: 0xfcfefe)
        static let surface = Color.white
        static let surfaceHover = Color(hex: 0xf3f8fa)
        static let group = secondaryPanel
        static let rowActive = Color.white
        static let selectionLocal = Color(hex: 0xe6edf0)
        static let hairline = Color(hex: 0x111111).opacity(0.08)
        static let borderControl = Color(hex: 0x111111).opacity(0.12)
        static let textPrimary = Color(hex: 0x111111)
        static let textSecondary = Color(hex: 0x606a70)
        static let textTertiary = Color(hex: 0x6f7578)
        static let textOnSidebar = Color(hex: 0x27343b)
        static let actionPrimary = Color(hex: 0x171919)
        static let actionHover = Color(hex: 0x2b3032)
        static let actionPressed = Color(hex: 0x080a0b)
        static let accent = Color(hex: 0x009af5)
        static let accentText = Color(hex: 0x006fc9)
        static let accentTint = Color(hex: 0xe5f4fe)
        static let accentTrack = accent
        static let accentPlate = accentTint
        static let success = Color(hex: 0x26735c)
        static let warning = Color(hex: 0x8a5700)
        static let error = Color(hex: 0xb42332)
        static let controlOff = Color(hex: 0xdde4e7)
        static let disabledSurface = Color(hex: 0xe6ecef)
        static let disabledText = Color(hex: 0x77838a)
        static let panelInset: CGFloat = 4
        static let panelRadius: CGFloat = 16
        static let sidebarWidth: CGFloat = 218
        static let cardRadius: CGFloat = 16
        static let smallCardRadius: CGFloat = 12
        static let rowRadius: CGFloat = 10
        static let buttonRadius: CGFloat = 10
        static let inputRadius: CGFloat = 10
        static let sheetRadius: CGFloat = 20
        static let pillRadius: CGFloat = 9999
        static let cardPadding: CGFloat = 20
        static let pagePadding: CGFloat = 32
        static let scrim = Color.black.opacity(0.24)
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let compact: CGFloat = 12
        static let regular: CGFloat = 16
        static let section: CGFloat = 24
        static let large: CGFloat = 32
        static let spacious: CGFloat = 48
    }

    /// System type for light windows only. The overlay retains `Font` below.
    enum LightFont {
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
        static func mono(_ size: CGFloat = 13) -> SwiftUI.Font { .system(size: size, design: .monospaced) }
        static func displayTracking(_ size: CGFloat) -> CGFloat { size >= 22 ? -0.02 * size : 0 }
        static let opticalNudge: CGFloat = 0
        static let pageTitle = body(22, weight: .medium)
        static let sectionTitle = body(16, weight: .medium)
        static let body = body(14)
        static let caption = body(12)
        enum Onboarding {
            static let hero = LightFont.body(40)
            static let title = LightFont.body(32)
            static let section = LightFont.body(20, weight: .medium)
            static let instruction = LightFont.body(18)
            static let body = LightFont.body(16)
            static let caption = LightFont.body(13)
            static let action = LightFont.body(16, weight: .medium)
        }
    }

    // MARK: - Overlay (dark ramp)

    /// Shared by the dark bar and companion panels, independently of the light window.
    enum Overlay {
        // Blends the native blur material, not its radius. 0 = clear; 1 = full material.
        static let glassBlurBlend: CGFloat = 0.70

        static let canvas = Color(hex: 0x141312)
        static let surface = Color(hex: 0x1e1c1a)
        static let hairline = Color(hex: 0x2e2b28)
        static let textPrimary = Color(hex: 0xfdfcfc)
        static let textSecondary = Color(hex: 0xa59f97)
        static let textTertiary = Color(hex: 0x777169)

        /// §4 hover-row spec: pills are transparent until hover, then step up to
        /// the hairline value — `surface` is too close to `canvas` to read.
        static let controlHover = hairline

        // §8 deviation 2 — compact density. The window's 20 pt card padding
        // leaves a 380 pt column on a 420 pt panel, which is not a usable body.
        static let labelSmall: CGFloat = 11
        static let labelMedium: CGFloat = 12
        static let labelLarge: CGFloat = 13
        static let bodySize: CGFloat = 14
        static let bodyLineSpacing: CGFloat = 7   // 14 pt × 1.5 line-height

        static let inputRadius: CGFloat = 10
        static let panelRadius: CGFloat = 20
        static let pillRadius: CGFloat = 9999

        /// §8 deviation 1 — the overlay floats over arbitrary wallpapers and
        /// needs a real shadow to read at all.
        static let shadowColor = Color.black.opacity(0.44)
        static let shadowRadius: CGFloat = 24
        static let shadowY: CGFloat = 8

        /// §8 deviation 4 — the capsule's rotating border, and the only colour the
        /// overlay has at all.
        ///
        /// **Measured off `reference/generating.png`, not chosen.** The two-stop
        /// `#0447ff` → `#ff4704` this used to be was the old ElevenLabs palette, and it
        /// is not what the reference shows: sampling the ring's peak-chroma pixel every
        /// 10° around the capsule gives a hue that sweeps a full circle — cyan at 3
        /// o'clock, blue at 6, violet and magenta up the left side, pink at 10, a warm
        /// coral at 12 and amber through green back to cyan. The stops below are that
        /// sweep, at the saturation the glow reads as before the blur washes it out.
        ///
        /// Fractions are SwiftUI's: 0 at 3 o'clock, increasing **clockwise**, which is
        /// the mirror of the angles the sample was taken at.
        ///
        /// The saturation is measured too, and it is lower than a first guess: scaled
        /// down to the reference capsule's own size, the ring there peaks at a chroma
        /// of 89 and a full-strength spectrum peaks at 154. These stops are HSL 62 %
        /// lightness, 72 % saturation — a step up from the 58/46 that first matched,
        /// because the line went from 1.5 pt to 1 pt and a thinner line at the same
        /// colour reads dimmer, and because the white bloom over it (see
        /// `GeneratingCapsule`) desaturates whatever it lands on. The bar sits over the
        /// user's wallpaper for a second at a time: it is a waiting indicator, not a
        /// light show.
        static var generatingGradient: AngularGradient {
            AngularGradient(
                stops: [
                    .init(color: Color(hex: 0x58e4e4), location: 0.00),
                    .init(color: Color(hex: 0x58c3e4), location: 0.13),
                    .init(color: Color(hex: 0x5874e4), location: 0.25),
                    .init(color: Color(hex: 0x9058e4), location: 0.35),
                    .init(color: Color(hex: 0xe458dd), location: 0.46),
                    .init(color: Color(hex: 0xe458a5), location: 0.58),
                    .init(color: Color(hex: 0xe45866), location: 0.72),
                    .init(color: Color(hex: 0xe4c858), location: 0.85),
                    .init(color: Color(hex: 0xa3e458), location: 0.93),
                    .init(color: Color(hex: 0x58e4e4), location: 1.00),
                ],
                center: .center
            )
        }
    }

    // MARK: - Type

    /// Inter, falling back to the system font until it is in the bundle. The
    /// window's hierarchy is carried by **weight** — 600 for numbers and titles,
    /// 500 for row labels, 400 for prose — not by size.
    enum Font {
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom("Inter", size: size).weight(weight)
        }

        /// Stat numbers and page titles. Same face as the body, heavier.
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .custom("Inter", size: size).weight(weight)
        }

        static func mono(_ size: CGFloat = 13) -> SwiftUI.Font {
            .custom("Geist Mono", size: size)
        }

        /// Slightly tightened above 18 pt, where a UI face set at display size
        /// otherwise reads loose.
        static func displayTracking(_ size: CGFloat) -> CGFloat {
            size >= 18 ? -0.01 * size : 0
        }

        /// How far a Japanese label's ink sits above the centre of the line box SwiftUI
        /// gives it. See `View.opticalCentre` for the measurement and what uses it.
        static let opticalNudge: CGFloat = 1.5
    }

    // MARK: - Overlay geometry (§4)

    enum Geometry {
        static let pillHeight: CGFloat = 28
        static let hoverRowHeight: CGFloat = 34
        static let inputBarHeight: CGFloat = 34
        static let pillCollapsedWidth: CGFloat = 44

        /// The input bar is the one state with a **fixed** width. Everywhere else the
        /// window follows SwiftUI's measurement, but a text field has no stable
        /// intrinsic width: it measures the placeholder while empty and the typed
        /// string after, so the window snapped narrower on the first keystroke and
        /// then twitched on every one after it. Worse, `fixedSize(horizontal:)` gives
        /// the field an unbounded ideal width, so a long prompt grew the window past
        /// the edge of the screen instead of wrapping.
        static let inputBarWidth: CGFloat = 360

        /// The reply context pill (§16). **A constant, not a measurement, and that is
        /// the point** — a measured height can inflate, and an inflated window near the
        /// bottom of the screen gets slid *down* by `clampToWorkArea` until its
        /// bottom-aligned content covers the bar. `ErrorPanel` documents the same
        /// failure. One line of `labelMedium` plus 9 pt either side.
        static let replyContextHeight: CGFloat = 30

        /// Between the context pill and the bar. `ErrorPanel` uses the same 8.
        static let replyContextGap: CGFloat = 8

        /// The update notice that stacks above the bar when Sparkle has quietly found a
        /// newer release. Same constant-height discipline as `replyContextHeight`, and
        /// for the same reason: this panel is long-lived and anchored near the bottom of
        /// the screen, which is exactly where an inflated measurement gets slid down
        /// over the bar by `clampToWorkArea`. Taller than the reply pill because it
        /// carries a real action, not just a quotation.
        static let updateNoticeHeight: CGFloat = 38
        static let updateNoticeWidth: CGFloat = 300

        /// Past this the field scrolls rather than growing. Three lines is roughly
        /// 90 Japanese characters at `inputBarWidth` — far more than a rewrite
        /// instruction needs, and short enough that the bar stays a bar.
        static let inputBarMaxLines: Int = 3

        /// Measured from the bottom of `OverlayPlacement.workArea` — the Dock's top
        /// edge when there is a Dock, the screen edge when there is not.
        static let bottomInset: CGFloat = 6

        static let snapTopInset: CGFloat = 0
        static let snapSideInset: CGFloat = 0
        static let snapEdgeThreshold: CGFloat = 120
        static let sideTabWidth: CGFloat = 24
        static let sideTabHeight: CGFloat = 56
        static let sideActionsWidth: CGFloat = 72
        static let sideActionsPadding: CGFloat = 8
        static let sideInputWidth: CGFloat = 208
        static let sideEditorHeight: CGFloat = 160
        static let sideInputMaxLines = 8
        static let sideCornerRadius: CGFloat = 18
        static let topCornerRadius: CGFloat = 8

        /// §4: without a grace delay, a diagonal path toward a far button
        /// collapses the row mid-travel.
        static let collapseGrace: TimeInterval = 0.3

        static let sideResultPanelWidth: CGFloat = 320
        static let sideResultPanelMaxHeight: CGFloat = 520
        static let sideResultBodyMaxHeight: CGFloat = 320
        static let sideGeneratingWidth: CGFloat = 176
        static let sideGeneratingHeight: CGFloat = 60
        static let resultPanelWidth: CGFloat = 420
        static let resultPanelMaxHeight: CGFloat = 440
        static let generatingCapsuleHeight: CGFloat = 36
        static let generatingCapsuleWidth: CGFloat = 176

        // Keep the visible capsule on the bar's line; the tight edge fits the Dock gap.
        static let generatingGlowPadding: CGFloat = 6
        static let generatingGlowSpread: CGFloat = 24

        static let errorToastWidth: CGFloat = 360

        /// The right-click snooze menu (§17). Narrower than the toast — a menu row is
        /// one line of Japanese plus a duration phrase, not a wrapped sentence.
        static let snoozeMenuWidth: CGFloat = 240
        static let snoozeMenuRowHeight: CGFloat = 28

        /// Bounds on the measured height. `ResultPanel` has always clamped its own and
        /// the toast never did, which is why one of them survived a bad measurement and
        /// the other threw itself off the bottom of the screen — see
        /// `ErrorPanel.applyContentHeight`. Even with the measurement fixed, an
        /// unbounded window height is not something a message should be able to ask for.
        static let errorToastMinHeight: CGFloat = 40
        static let errorToastMaxHeight: CGFloat = 160

        /// Long enough to read a two-line Japanese sentence, short enough that a stale
        /// message is never mistaken for the current state.
        ///
        /// It was 5, but the timeout was never what people were reading against: a
        /// toast raised from `.hoverRow` used to die on the next state change, and the
        /// next state change is the row collapsing 300 ms after the pointer leaves —
        /// i.e. the moment you look up at the message. See `OverlayController.transition`.
        static let errorToastDuration: TimeInterval = 8

        /// The result body scrolls past this and the panel stops growing. Below it the
        /// panel shrinks to the text — a fixed height wrapped a one-line rewrite in
        /// ~250 pt of empty canvas, which is the slab `debug.png` shows.
        static let resultBodyMaxHeight: CGFloat = 240
        static let resultBodyMinHeight: CGFloat = 44

    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
