import AppKit
import ApplicationServices
import SwiftUI
import DesktopRewriteKit

/// Fixed destinations; legacy free-position offsets are retired on first restore.
enum OverlayPlacement {
    private static let offsetKey = "overlay.pill.offsetFromVisibleFrameOrigin"
    private static let zoneKey = "overlay.pill.snapZone"

    /// The screen under the mouse cursor, falling back to `.main`. Same rule
    /// `prompt/src/core/window-manager.js` `positionOverlay()` uses.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screen a window is actually **on** — the one containing its centre.
    ///
    /// Deliberately not `activeScreen()`. The position poll compares the work area of
    /// whichever screen the *mouse* is over, so on a two-display setup merely moving
    /// the cursor to the other display changed the answer, triggered a re-anchor, and
    /// clamped the bar onto that display at an X carried over from the one it left.
    /// The bar is draggable: it belongs where it was put, not where the pointer is.
    static func screen(containing frame: NSRect) -> NSScreen {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? activeScreen()
    }

    /// Keeps a frame inside the work area of whichever screen it is on.
    ///
    /// Resolved from the frame rather than `NSWindow.screen`, which returns nil once a
    /// window is fully off-screen — precisely the case a clamp exists to handle.
    static func clampToWorkArea(_ frame: NSRect) -> NSRect {
        clamp(frame, to: workArea(on: screen(containing: frame)))
    }

    /// The insets every snap slot sits off its edge — `bottomInset` and its mirrors.
    static var slotInsets: BarSlotInsets {
        BarSlotInsets(
            bottom: Tokens.Geometry.bottomInset,
            top: Tokens.Geometry.snapTopInset,
            side: Tokens.Geometry.snapSideInset
        )
    }

    /// Places an auxiliary panel — the generating capsule, the result card — in the
    /// bar's place, on the side of it with more room (`BarPlacement.replaceFrame`).
    ///
    /// The clamp is the point. These were centred on the bar with no bounds check at
    /// all, and the bar is draggable with a persisted position, so parking it near a
    /// screen edge left a 420 pt result card hanging off the side.
    static func auxiliaryFrame(size: NSSize, anchoredTo bar: NSRect) -> NSRect {
        BarPlacement.replaceFrame(size: size, bar: bar, workArea: workArea(on: screen(containing: bar)))
    }

    /// Which side of the bar a stacked panel grows into. The one question every
    /// above-anchored panel used to answer "above" in its own file; now they all ask
    /// this, so a top-docked bar's toast, reply card and result hang *below* it.
    static func verticalSide(anchoredTo bar: NSRect) -> VerticalAnchorSide {
        BarPlacement.verticalSide(ofBar: bar, in: workArea(on: screen(containing: bar)))
    }

    /// Places a panel that stacks `gap` beyond another's near edge — the error toast,
    /// the reply context card, the update notice, the snooze menu.
    static func stackedFrame(size: NSSize, gap: CGFloat, anchoredTo anchor: NSRect) -> NSRect {
        BarPlacement.stackedFrame(
            size: size,
            gap: gap,
            anchor: anchor,
            workArea: workArea(on: screen(containing: anchor))
        )
    }

    /// The resting frame a zone parks the bar at, for the bar's current size.
    static func zoneFrame(_ zone: SnapZone, barSize: NSSize, on screen: NSScreen) -> NSRect {
        BarPlacement.zoneFrame(zone, barSize: barSize, workArea: workArea(on: screen),
                               insets: slotInsets, notch: notchFrame(on: screen))
    }

    static func notchFrame(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                      width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    static func slotFrames(on screen: NSScreen, active: SnapZone? = nil) -> [SnapZone: NSRect] {
        let area = workArea(on: screen)
        let notch = notchFrame(on: screen)
        return Dictionary(uniqueKeysWithValues: SnapZone.allCases.map { zone in
            let grows = active == zone
            let size: NSSize
            switch zone {
            case .bottomCenter:
                size = NSSize(width: grows ? 112 : 72, height: grows ? 56 : 40)
            case .topCenter:
                size = NSSize(width: max(notch?.width ?? 72, 72) + (grows ? 32 : 0),
                              height: grows ? 56 : 36)
            case .left, .right:
                size = NSSize(width: grows ? 56 : 36, height: grows ? 112 : 72)
            }
            return (zone, BarPlacement.zoneFrame(zone, barSize: size, workArea: area,
                                                  insets: slotInsets, notch: notch))
        })
    }

    static func activeSnapZone(near bar: NSRect, on screen: NSScreen) -> SnapZone? {
        BarPlacement.activeZone(near: bar, slots: slotFrames(on: screen),
                                threshold: Tokens.Geometry.snapEdgeThreshold)
    }

    /// `visibleFrame`, corrected at the bottom edge and capped below the camera
    /// housing at the top.
    ///
    /// **`visibleFrame` on its own is wrong, and not marginally.** Measured on a
    /// 1920×1080 display while a full-screen space had the Dock hidden: the Dock's own
    /// AX element put its top edge at the screen's bottom — gone — while `visibleFrame`
    /// still reported `minY = 78`. No notification fires for that, and polling
    /// `visibleFrame` cannot see it either, because the value never changes. So the
    /// bar hung 78 pt above the bottom of every full-screen app.
    ///
    /// `DockProbe` decides whether the Dock is really down there. Only then is
    /// `visibleFrame.minY` trusted; otherwise the work area runs to the screen edge.
    ///
    /// The notch cap only bites in a full-screen space: windowed, `visibleFrame` already
    /// stops below the menu bar — which on a notched display is exactly the housing's
    /// height — so `area.maxY` equals the cap and nothing moves. Full-screen, the menu
    /// bar is gone and `visibleFrame` runs to the frame top, through the housing; the
    /// cap pulls it back so a top zone parks below the cutout, not behind it.
    /// `safeAreaInsets.top` is 0 on displays without a housing, so those are untouched.
    static func workArea(on screen: NSScreen) -> NSRect {
        var area = screen.visibleFrame
        if AXIsProcessTrusted(), !DockProbe.occupiesBottom(of: screen) {
            area.size.height += area.minY - screen.frame.minY
            area.origin.y = screen.frame.minY
        }
        if screen.safeAreaInsets.top > 0 {
            let belowHousing = screen.frame.maxY - screen.safeAreaInsets.top
            if area.maxY > belowHousing {
                area.size.height -= area.maxY - belowHousing
            }
        }
        return area
    }

    static func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        zoneFrame(savedZone(), barSize: size, on: screen)
    }

    static func reframe(_ current: NSRect, to size: NSSize, on screen: NSScreen) -> NSRect {
        frame(for: size, on: screen)
    }

    static func persist(zone: SnapZone) {
        UserDefaults.standard.set(zone.rawValue, forKey: zoneKey)
        UserDefaults.standard.removeObject(forKey: offsetKey)
    }

    static func resetPosition() {
        persist(zone: .bottomCenter)
    }

    static func savedZone() -> SnapZone {
        let raw = UserDefaults.standard.string(forKey: zoneKey)
        let zone = SnapZone.restored(from: raw)
        if raw != zone.rawValue || UserDefaults.standard.object(forKey: offsetKey) != nil {
            persist(zone: zone)
        }
        return zone
    }

    private static func clamp(_ rect: NSRect, to area: NSRect) -> NSRect {
        BarPlacement.clamp(rect, to: area)
    }
}

struct CompanionGeometry: Equatable {
    let zone: SnapZone
    let anchor: NSRect
    let workArea: NSRect
    var notchWidth: CGFloat = 0

    init(zone: SnapZone, anchor: NSRect, workArea: NSRect, notchWidth: CGFloat = 0) {
        self.zone = zone
        self.anchor = anchor
        self.workArea = workArea
        self.notchWidth = notchWidth
    }

    init(zone: SnapZone, anchor: NSRect, screen: NSScreen) {
        self.init(zone: zone, anchor: anchor, workArea: OverlayPlacement.workArea(on: screen),
                  notchWidth: OverlayPlacement.notchFrame(on: screen)?.width ?? 0)
    }

    private var isSide: Bool { zone == .left || zone == .right }

    var resultWidth: CGFloat {
        let width = isSide ? Tokens.Geometry.sideResultPanelWidth : Tokens.Geometry.resultPanelWidth
        return min(workArea.width, max(width, zone == .topCenter ? notchWidth : 0))
    }

    var resultMaxHeight: CGFloat {
        min(workArea.height, isSide ? Tokens.Geometry.sideResultPanelMaxHeight : Tokens.Geometry.resultPanelMaxHeight)
    }

    var resultBodyMaxHeight: CGFloat {
        isSide ? Tokens.Geometry.sideResultBodyMaxHeight : Tokens.Geometry.resultBodyMaxHeight
    }

    var generationSize: NSSize {
        let size: NSSize
        switch zone {
        case .bottomCenter:
            size = NSSize(width: Tokens.Geometry.generatingCapsuleWidth, height: Tokens.Geometry.generatingCapsuleHeight)
        case .topCenter:
            size = NSSize(width: max(208, notchWidth), height: 40)
        case .left, .right:
            size = NSSize(width: Tokens.Geometry.sideGeneratingWidth, height: Tokens.Geometry.sideGeneratingHeight)
        }
        return NSSize(width: min(size.width, workArea.width), height: min(size.height, workArea.height))
    }

    func frame(size: NSSize) -> NSRect {
        BarPlacement.attachedFrame(size: size, zone: zone, anchor: anchor, workArea: workArea)
    }
}


extension SnapZone {
    func companionShape(generating: Bool = false) -> UnevenRoundedRectangle {
        let radius: CGFloat
        switch self {
        case .bottomCenter: radius = generating ? 18 : Tokens.Overlay.panelRadius
        case .topCenter: radius = Tokens.Geometry.topCornerRadius
        case .left, .right: radius = Tokens.Geometry.sideCornerRadius
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: self == .left || self == .topCenter ? 0 : radius,
            bottomLeadingRadius: self == .left ? 0 : radius,
            bottomTrailingRadius: self == .right ? 0 : radius,
            topTrailingRadius: self == .right || self == .topCenter ? 0 : radius,
            style: .continuous)
    }

    var companionAlignment: Alignment {
        switch self {
        case .bottomCenter: return .bottom
        case .topCenter: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }
}
