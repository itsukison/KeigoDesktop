import SwiftUI

/// The window's glyphs — Reicon Outline, not SF Symbols.
///
/// SF Symbols draw at the system's own weights and optical sizes, which read as macOS
/// chrome rather than as this app's; Reicon's outline set is a single 24×24 grid at one
/// hairline weight, which is what makes a row of them look drawn by one hand. The
/// assets are template images (`App/Resources/Icons.xcassets`), so they take
/// `foregroundStyle` like any other symbol.
///
/// Names are roles, not pictures. `Icon.Name` is the only place the mapping to Reicon's
/// own names lives; the README beside the catalog carries the table.
struct Icon: View {
    enum Name: String {
        /// The product mark. Not Reicon — the keycap, as line art. See the catalog README.
        case mark = "icon-mark"
        case home = "icon-home"
        case buttons = "icon-buttons"
        case settings = "icon-settings"
        case search = "icon-search"
        case add = "icon-add"
        case edit = "icon-edit"
        case trash = "icon-trash"
        case arrowUp = "icon-arrow-up"
        case arrowDown = "icon-arrow-down"
        case copy = "icon-copy"
        case user = "icon-user"
        case profile = "icon-profile"
        case wand = "icon-wand"
        case accessibility = "icon-accessibility"
        case history = "icon-history"
        case noteAdd = "icon-note-add"
        case close = "icon-close"
        case check = "icon-check"
        case sliders = "icon-sliders"
        case info = "icon-info"
        case window = "icon-window"
        /// Drawn to Reicon's grid rather than extracted from it — the set has no card
        /// glyph. Filled outline at the same 1.5 px effective weight as the rest, so
        /// it sits in the nav beside them without reading as a second hand.
        case plan = "icon-plan"

        /// The one asset that is not a template, so it cannot be an `Icon`: the mark in
        /// full colour, for the overlay's dark ramp. Named here anyway so the catalog
        /// mapping still lives in exactly one file. Kept as the static source/fallback
        /// for `BrandGlyph`'s generated animation atlases.
        ///
        /// `-filled`, not `-color`: Xcode generates `iconMark` as the symbol for both
        /// `icon-mark` and `icon-mark-color`, and warns about the collision.
        static let markFilled = "icon-mark-filled"
    }

    let name: Name
    var size: CGFloat = 16

    init(_ name: Name, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name.rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
