import AppKit
// `tr` for the one component here whose text is its own rather than the caller's:
// Google's button owns its wording as much as its logo, and splitting the two would
// put the same three strings back in two feature folders — which is how アカウント and
// onboarding drifted apart in the first place.
import DesktopRewriteKit
import SwiftUI

/// The one thing that changes the cursor over a window that can never be key.
///
/// **The root cause of "the overlay never shows a pointer" is `addCursorRect`, which is
/// what this used to be alone.** Cursor rectangles are in effect only in the **key**
/// window, and §2 forbids the pill from ever becoming key — so every control on the bar
/// was stuck with an arrow no matter what it declared, while the identical code worked
/// in the main window, which *is* key. That much is documented behaviour and matches the
/// symptom exactly.
///
/// The non-key-window path is `.mouseEnteredAndExited` plus `.mouseMoved`; its window
/// must set `acceptsMouseMovedEvents = true` or the reassertion below is dead code.
/// `NSTrackingArea` turns out to be unreachable by any synthetic pointer:
/// moving the window under a stationary pointer, `CGWarpMouseCursorPosition`, and posted
/// `.mouseMoved` events at the HID tap all produced *zero* enter/exit callbacks, even for
/// a plain `NSView` with no SwiftUI in the way — AppKit only recomputes tracking on real
/// HID motion. Each mechanism below covers a different cursor lifecycle:
///
/// - `addCursorRect` — the only one AppKit re-asserts on every mouse-moved, which is
///   what keeps the cursor from flickering back to an arrow. Key windows only.
/// - `.mouseEnteredAndExited` + `.activeAlways` — the one channel Apple documents as
///   reaching a non-key window in a non-active app. `NSCursor.set()` inside it is what
///   is expected to carry the overlay.
/// - `.mouseMoved` on the same area — re-asserts the cursor if anything else (SwiftUI's
///   own hosting-view pointer handling, most likely) resets it after the enter.
///
/// **Not `NSCursor.push()` / `pop()`**, which is the usual SwiftUI trick and leaks: a
/// hover that ends because the view was *removed* rather than exited never pops, and
/// reordering a list removes hovered views constantly. `CursorStack` is keyed by view
/// identity rather than being a stack of pushes, so a lost exit is a stale entry that
/// the next event drops, not a permanently wrong cursor.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectView {
        CursorRectView(cursor: cursor)
    }

    func updateNSView(_ view: CursorRectView, context: Context) {
        view.cursor = cursor
    }

    final class CursorRectView: NSView {
        var cursor: NSCursor {
            didSet {
                guard cursor != oldValue else { return }
                window?.invalidateCursorRects(for: self)
                if isInside { CursorStack.shared.enter(self, cursor) }
            }
        }

        private var isInside = false

        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// This view observes pointer movement; it is never the control being clicked.
        /// Returning itself here can make the AppKit bridge consume a click before the
        /// SwiftUI button above it, especially when a dynamic list rebuilds its rows.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            isInside = true
            CursorStack.shared.enter(self, cursor)
        }

        override func mouseExited(with event: NSEvent) {
            isInside = false
            CursorStack.shared.exit(self)
        }

        /// Re-assert, in case something set the cursor back between enter and exit.
        /// `NSCursor.set()` is a couple of instructions; a mouse-moved that changes
        /// nothing is cheaper than a cursor that silently reverts.
        override func mouseMoved(with event: NSEvent) {
            CursorStack.shared.reassert(self)
        }

        /// The leak the push/pop version could not close: SwiftUI tearing the view out
        /// from under a pointer that never left it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window == nil else { return }
            isInside = false
            CursorStack.shared.exit(self)
        }

        /// Key windows only, and deliberately duplicated — see the type's note.
        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

/// Which of the overlapping cursor areas under the pointer wins.
///
/// A `CursorArea` installed with `.background` fires enter/exit on geometry, not on
/// hit-testing, so a prompt pill's area and the bar's own area are *both* entered — the
/// pill has to win, and giving the bar back its `.openHand` when the pill is left has to
/// happen without the bar seeing a second enter. Most-recently-entered wins, and an area
/// leaving the hierarchy drops out of the set wherever it was in it.
@MainActor
final class CursorStack {
    static let shared = CursorStack()

    private var entries: [(view: ObjectIdentifier, cursor: NSCursor)] = []

    private init() {}

    func enter(_ view: NSView, _ cursor: NSCursor) {
        let id = ObjectIdentifier(view)
        entries.removeAll { $0.view == id }
        entries.append((id, cursor))
        apply()
    }

    func exit(_ view: NSView) {
        let id = ObjectIdentifier(view)
        guard entries.contains(where: { $0.view == id }) else { return }
        entries.removeAll { $0.view == id }
        apply()
    }

    /// Re-applies the winning cursor, and **only if the caller is the one that won**.
    /// The pointer is inside the bar's area and a pill's area at the same time, so both
    /// get `mouseMoved`; re-entering on every one of them would let whichever fired last
    /// take the cursor, and the bar's `.openHand` would keep stealing it back from the
    /// pill under the pointer.
    func reassert(_ view: NSView) {
        guard entries.last?.view == ObjectIdentifier(view) else { return }
        apply()
    }

    /// For a window that is ordered out from under a stationary pointer — pressing a
    /// prompt pill hides the bar and puts the generating capsule where it was, and
    /// there is no exit event for a window that simply stops being on screen.
    func releaseAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        apply()
    }

    private func apply() {
        (entries.last?.cursor ?? .arrow).set()
    }
}

extension View {
    /// Anything clickable or draggable says so under the pointer.
    func cursor(_ cursor: NSCursor) -> some View {
        background(CursorArea(cursor: cursor))
    }

    /// Lifts a glyph onto the optical centre of the Japanese label beside it.
    ///
    /// SwiftUI centres a `Text` by its **line box**, and the line box a Japanese string
    /// gets carries more space under the glyphs than over them: measured with
    /// `ImageRenderer`, 「ホーム」 at 14 pt inks from 22.5 to 34.5 inside a 60 pt frame,
    /// i.e. its own centre sits 1.5 pt above the box's. A glyph centred in the same
    /// `HStack` is therefore centred against nothing the eye can see, and reads as
    /// sitting low against its label — which is exactly what the sidebar looked like.
    ///
    /// The correction is a constant because the gap is: it measured 1.4–2.1 pt across
    /// 11–15 pt, on katakana, kanji and Latin alike. Applied to the **glyph**, not the
    /// text, so nothing about type rendering changes.
    ///
    /// Only for a glyph that is a *sibling* of the label. A container drawn **around**
    /// the label needs `opticalPadding` instead — offsetting the text inside its own
    /// plate moves the ink and leaves the plate where it was, which is the same error
    /// twice over.
    func opticalCentre() -> some View {
        offset(y: -Tokens.Font.opticalNudge)
    }

    /// Padding that centres a plate on its label's **ink** rather than on its line box.
    ///
    /// The other half of `opticalCentre`: same measurement, applied to the container.
    /// Symmetric padding around a Japanese label leaves visibly more air underneath it
    /// than above — measured on the メイン badge at 4/4, the gaps came out 3.5 pt over
    /// and 6.5 pt under — so the vertical padding is biased by the nudge and the plate
    /// lands centred on what the eye actually sees.
    func opticalPadding(vertical: CGFloat, horizontal: CGFloat) -> some View {
        padding(.top, vertical + Tokens.Font.opticalNudge)
            .padding(.bottom, vertical - Tokens.Font.opticalNudge)
            .padding(.horizontal, horizontal)
    }
}

// MARK: - Surfaces

/// The window's one card: **white on white, told apart by its border.**
///
/// This is the inversion at the centre of the restyle. The old system separated a
/// card from the page by filling it a shade deeper than the canvas; `design.md`'s
/// cards sit on a white panel at the same white and are bounded by a 1 pt hairline
/// instead. Everything downstream — history rows, button rows, settings groups —
/// follows from that one change.
struct Card<Content: View>: View {
    var padding: CGFloat = Tokens.Window.cardPadding
    var radius: CGFloat = Tokens.Window.cardRadius
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Tokens.Window.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Tokens.Window.hairline, lineWidth: 1)
        )
    }
}

/// A card of rows, each separated by a hairline that stops short of the border.
///
/// `design.md`'s settings pattern, and the shape the history list and the button
/// list both take: the group owns the border, the rows own their own insets.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
                .fill(Tokens.Window.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
                .strokeBorder(Tokens.Window.hairline, lineWidth: 1)
        )
        // The last row's own rounded corners would otherwise poke past the group's.
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous))
    }
}

/// A title, an optional second line, and a control on the right. `design.md`'s
/// settings row, used anywhere a switch or a button needs explaining.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Tokens.Font.body(14, weight: .medium))
                    .foregroundStyle(Tokens.Window.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 1 px `#ececee`. The system separates with borders, not shadows.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.Window.hairline)
            .frame(height: 1)
    }
}

// MARK: - Type

/// A page opens with a 20 pt semibold title and one or two quiet lines under it.
///
/// Not a 32 pt display line: `design.md`'s type hierarchy is carried by weight, and
/// its own pages ("Style Matching", "Team Members") set their titles two steps below
/// where the old system put them.
struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The label above a group of cards — "Fundamentals", "Tone". Quiet, small, and
/// outside the card it introduces.
struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Tokens.Font.body(12, weight: .medium))
            .foregroundStyle(Tokens.Window.textTertiary)
    }
}

/// A section's own heading, with an optional accent link on the far right —
/// `design.md`'s "Learning Center … Open Learning Center" row.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(Tokens.Font.body(15, weight: .medium))
                .foregroundStyle(Tokens.Window.textPrimary)
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// `design.md`'s badge: a 9999 pt `#e4e5f0` plate with `#5856b5` medium text.
///
/// One object, two call sites — the メイン slot marker and the history list's button
/// label. They were written separately and drifted: 11/7/1 and 12/8/2, both of which
/// squeeze the plate onto the text. The plate needs to read as a plate, so the padding
/// is 8/4 — and it is `opticalPadding`, because half of "the badge needs padding" was
/// never the amount: symmetric padding around katakana leaves the glyphs sitting high
/// in the capsule, and a plate that is bottom-heavy looks cramped however much air it
/// is given.
struct Badge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Tokens.Font.body(12, weight: .medium))
            .foregroundStyle(Tokens.Window.accentText)
            .opticalPadding(vertical: 4, horizontal: 8)
            .background(Capsule().fill(Tokens.Window.accentPlate))
    }
}

/// Text that acts. The accent is allowed here — under the old system it was not.
struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}

// MARK: - Buttons

/// Google's own button, not one of ours.
///
/// It is deliberately outside `ActionButton`'s two axes: the white plate, the
/// `#747775` border, the `#1f1f1f` label and the full-colour G are Google's identity
/// guidelines, and a `.secondary` `ActionButton` reading 「Google で続ける」 with no mark
/// on it — which is what アカウント shipped — is both off-brand and the one button on
/// the page a user scans for by its logo.
///
/// Two sizes because it appears in two shapes of layout: `wide` fills the column in
/// first run, where it is the primary way in; `inline` matches `ActionButton`'s 32 pt
/// row metrics for アカウント, where it stands beside サインイン. Everything else about
/// the two is identical, which is the point of having one type.
struct GoogleSignInButton: View {
    enum Size {
        case wide
        case inline

        var height: CGFloat { self == .wide ? 42 : 32 }
        var glyph: CGFloat { self == .wide ? 18 : 16 }
        var spacing: CGFloat { self == .wide ? 12 : 8 }
        var font: CGFloat { self == .wide ? 14 : 13 }
    }

    var size: Size = .wide
    var isLoading: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.spacing) {
                Image("GoogleG")
                    .resizable()
                    .interpolation(.high)
                    // The artwork is 200×204, so a square frame alone squashes the G by
                    // 2%. Fitting inside the square is what keeps it Google's mark.
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.glyph, height: size.glyph)
                Text(
                    isLoading
                        ? tr("接続中…", "Connecting…", "连接中…")
                        : tr("Google で続ける", "Continue with Google", "使用 Google 继续")
                )
                .font(Tokens.Font.body(size.font, weight: .medium))
                .foregroundStyle(Color(hex: 0x1f1f1f))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, size == .wide ? 0 : 14)
            .frame(maxWidth: size == .wide ? .infinity : nil)
            .frame(height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Tokens.Window.surface : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: 0x747775), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .cursor(isLoading ? .arrow : .pointingHand)
    }
}

/// One button with two axes: how loud it is, and what shape it takes.
///
/// `design.md` uses an 8 pt rounded rectangle for actions that live in a row and a
/// full pill for the few that are meant to be seen from across the window. The
/// primary fill is the accent, which is the rule the previous system forbade
/// outright — filled ink was the only primary it allowed.
struct ActionButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
    }

    enum Shape {
        case rounded
        case pill
    }

    let title: String
    var icon: Icon.Name?
    var style: Style = .primary
    var shape: Shape = .rounded
    var enabled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    init(
        _ title: String,
        icon: Icon.Name? = nil,
        style: Style = .primary,
        shape: Shape = .rounded,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.shape = shape
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Icon(icon, size: 14)
                }
                Text(title)
                    .font(Tokens.Font.body(13, weight: .medium))
                    // A 32 pt button has room for exactly one line, so wrapping is never
                    // an outcome it can render — it can only clip. 保存 in a row that ran
                    // out of width broke between its two characters and lost both halves'
                    // descenders. Refusing to compress is the honest behaviour: the label
                    // keeps its intrinsic width and the row's flexible parts give way.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, shape == .pill ? 18 : 14)
            .frame(height: 32)
            .background(background)
            .overlay(border)
            .clipShape(clipShape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .cursor(enabled ? .pointingHand : .arrow)
    }

    private var radius: CGFloat {
        shape == .pill ? Tokens.Window.pillRadius : Tokens.Window.buttonRadius
    }

    private var clipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var foreground: Color {
        guard enabled else { return Tokens.Window.textTertiary }
        switch style {
        case .primary: return .white
        case .secondary, .ghost: return Tokens.Window.textPrimary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            clipShape.fill(
                enabled
                    ? Tokens.Window.accent.opacity(hovering ? 0.88 : 1)
                    : Tokens.Window.controlOff
            )
        case .secondary:
            clipShape.fill(hovering && enabled ? Tokens.Window.surface : Tokens.Window.canvas)
        case .ghost:
            clipShape.fill(hovering && enabled ? Tokens.Window.surface : .clear)
        }
    }

    @ViewBuilder
    private var border: some View {
        if style == .secondary {
            clipShape.strokeBorder(Tokens.Window.hairline, lineWidth: 1)
        }
    }
}

/// A borderless glyph — edit, delete, copy. Transparent until hover.
struct IconButton: View {
    let icon: Icon.Name
    var help: String = ""
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 15)
                .foregroundStyle(
                    enabled ? Tokens.Window.textSecondary : Tokens.Window.controlOff
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Window.rowRadius, style: .continuous)
                        .fill(hovering && enabled ? Tokens.Window.surface : .clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hovering = $0 }
        .cursor(enabled ? .pointingHand : .arrow)
    }
}

/// The circular glyph button `design.md` puts at the top-right of a page and at the
/// corner of a sheet — a filled grey disc rather than a bare icon.
struct RoundIconButton: View {
    let icon: Icon.Name
    var help: String = ""
    var diameter: CGFloat = 30
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: diameter * 0.42)
                .foregroundStyle(Tokens.Window.textSecondary)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle().fill(hovering ? Tokens.Window.rowActive : Tokens.Window.surface)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }
}

// MARK: - Inputs

/// **A fill, not a box.** `design.md`'s inputs are `#f7f7f8` rounded rectangles with
/// no border at all — the tone does the work a border would, and a page of them has
/// no outlines on it. A border appears only on focus, and it is the accent.
///
/// That focus colour is the second half of the accent rule reversing: the old system
/// named focus rings as somewhere the accent must never appear, so focus was carried
/// by border *weight* instead.
struct FieldBackground: View {
    var focused = false

    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.Window.inputRadius, style: .continuous)
            .fill(Tokens.Window.group)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Window.inputRadius, style: .continuous)
                    .strokeBorder(focused ? Tokens.Window.accent : .clear, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// A text field that shows where the keyboard is.
///
/// A bare `TextField(.plain)` draws no focus indication at all, so a form of three
/// stacked fields gave no clue which one was taking the typing. `@FocusState` has to
/// live next to the field it tracks, which is why this is a view rather than a
/// modifier.
struct SettingsField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(Tokens.Font.body(14))
        .foregroundStyle(Tokens.Window.textPrimary)
        .focused($focused)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(FieldBackground(focused: focused))
        .onSubmit(onSubmit)
    }
}

/// The search pill: a filled capsule with a magnifier, no border. `design.md` uses
/// it wherever a list is long enough to need filtering.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 200

    var body: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 14)
                .foregroundStyle(Tokens.Window.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textPrimary)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 30)
        .background(Capsule().fill(Tokens.Window.surface))
    }
}

/// Green for done, grey for not. `design.md` has exactly one non-accent colour and
/// this is where it goes.
struct StatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Tokens.Window.success : Tokens.Window.controlOff)
            .frame(width: 8, height: 8)
    }
}

extension View {
    /// Every switch in the window is the same accent switch.
    func accentSwitch() -> some View {
        toggleStyle(.switch).tint(Tokens.Window.accent)
    }
}
