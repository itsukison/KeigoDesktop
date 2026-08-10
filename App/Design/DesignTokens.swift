import SwiftUI

/// Two ramps, per AGENTS.md §8.
///
/// `Window` is `design.md`'s published system — Willow's, sampled from
/// `reference/`. `Overlay` is the dark ramp the bar, the capsule and the result
/// card are drawn from; it is its own ramp, not a derivation of the light one.
enum Tokens {

    // MARK: - design.md palette, verbatim

    /// Measured off `reference/Screenshot 2026-08-07 at 19.14.*.png` rather than
    /// eyeballed — the values with a pixel behind them are marked in `design.md`.
    enum Palette {
        /// The window itself, visible as a margin around the content panel.
        static let shell = Color(hex: 0xf2f2f4)
        /// The sidebar's own fill. It sits under an `.sidebar` vibrancy material,
        /// so this is the value it lands on over a light desktop.
        static let sidebar = Color(hex: 0xf5f6f7)
        /// The content panel and every card on it. Pure white, not an off-white.
        static let white = Color(hex: 0xffffff)
        /// Search fields, icon plates, quiet fills.
        static let mist = Color(hex: 0xf5f5f5)
        /// Grouped containers that hold cards of their own.
        static let fog = Color(hex: 0xf7f7f8)
        /// The active sidebar row. Willow's selection **darkens**; it does not lift.
        static let cloud = Color(hex: 0xededef)
        /// Card borders and separators. Cards read by their border, not their fill.
        static let hairline = Color(hex: 0xececee)

        static let ink = Color(hex: 0x4e4d51)
        static let slate = Color(hex: 0x8a8a90)
        static let ash = Color(hex: 0xb3b3b8)

        /// The accent, and it is UI chrome: filled buttons, toggles, links, badges,
        /// selection. This is the single largest break from the system this file
        /// used to hold, where the accents were forbidden on all four of those.
        static let indigo = Color(hex: 0x5a57ba)
        /// The same hue as type — links and badge labels, where the fill weight of
        /// `indigo` would be too heavy.
        static let indigoText = Color(hex: 0x5856b5)
        /// Filled accent surfaces: the plan card, an active tint.
        static let indigoTint = Color(hex: 0xedeefa)
        /// The lighter tint a switch's track takes when it is on.
        static let indigoTrack = Color(hex: 0xe6e5fd)
        /// Badge plates — a step greyer than `indigoTint`.
        static let indigoPlate = Color(hex: 0xe4e5f0)

        /// Completed, granted, connected. The one non-accent colour in the system.
        static let green = Color(hex: 0x46a588)
        /// A switch that is off, and any control track behind one.
        static let controlOff = Color(hex: 0xd9d9da)
    }

    // MARK: - Window (the published system)

    enum Window {
        static let shell = Palette.shell
        static let sidebar = Palette.sidebar
        static let canvas = Palette.white
        static let surface = Palette.mist
        static let group = Palette.fog
        static let rowActive = Palette.cloud
        static let hairline = Palette.hairline

        static let textPrimary = Palette.ink
        static let textSecondary = Palette.slate
        static let textTertiary = Palette.ash

        static let accent = Palette.indigo
        static let accentText = Palette.indigoText
        static let accentTint = Palette.indigoTint
        static let accentTrack = Palette.indigoTrack
        static let accentPlate = Palette.indigoPlate
        static let success = Palette.green
        static let controlOff = Palette.controlOff

        /// The content panel floats inside the window with the shell showing around
        /// it — measured at 4 pt on three sides, with the sidebar taking the fourth.
        static let panelInset: CGFloat = 4
        static let panelRadius: CGFloat = 12
        static let sidebarWidth: CGFloat = 218

        static let cardRadius: CGFloat = 16
        static let smallCardRadius: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let buttonRadius: CGFloat = 8
        static let inputRadius: CGFloat = 8
        static let sheetRadius: CGFloat = 24
        static let pillRadius: CGFloat = 9999

        static let cardPadding: CGFloat = 20
        static let pagePadding: CGFloat = 32

        /// The modal scrim. Willow's settings sheet dims the window to `#919191`
        /// over white, which is 40% black.
        static let scrim = Color.black.opacity(0.4)
    }

    // MARK: - Overlay (dark ramp)

    /// Unchanged by the restyle. The bar is the one path that has run end to end,
    /// and it is drawn over arbitrary wallpaper rather than over `Window.canvas`,
    /// so it answers to nothing in the ramp above.
    enum Overlay {
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

        /// §4: without a grace delay, a diagonal path toward a far button
        /// collapses the row mid-travel.
        static let collapseGrace: TimeInterval = 0.3

        static let resultPanelWidth: CGFloat = 420
        static let resultPanelMaxHeight: CGFloat = 440
        static let generatingCapsuleHeight: CGFloat = 36
        static let generatingCapsuleWidth: CGFloat = 176

        /// Room around the capsule for its glow to fall on. `generating.png`'s border
        /// is a bloom, not a hairline — measured perpendicular to the ring, the core is
        /// one pixel with ~8 pt of falloff either side — and the window is otherwise
        /// sized exactly to the capsule, so without this the glow is clipped to the
        /// shape that casts it.
        ///
        /// **Asymmetric, and that is the point.** The bottom is pinned to `bottomInset`
        /// because that is the only slack there is: the bar sits 6 pt above the work
        /// area, so 6 pt of window can hang below the capsule and still leave the
        /// capsule's own bottom edge on the bar's line. Above and to the sides there is
        /// no such limit, and that is where the halo is actually seen — the bottom of
        /// it is against the Dock or the screen edge either way.
        static let generatingGlowPadding: CGFloat = 6
        static let generatingGlowSpread: CGFloat = 11

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

        /// Floor for the **whole card**, not the body. Header, prompt echo and footer
        /// alone come to roughly 180 pt, so flooring the window at `resultBodyMinHeight`
        /// was flooring it at a third of its own chrome.
        static let resultPanelMinHeight: CGFloat = 160
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
