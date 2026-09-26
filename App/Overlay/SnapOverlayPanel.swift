import AppKit
import DesktopRewriteKit
import SwiftUI

/// A non-interactive screen scrim with four bright, expanding landing areas.
final class SnapOverlayPanel: NSPanel {

    let model = SnapOverlayModel()

    /// The `CGDirectDisplayID` the slots were computed for. `OverlayController`
    /// compares it on every move so a drag that crosses to another display gets a
    /// new overlay on that display, rather than slot outlines pointing at the edges
    /// of a screen the bar is no longer on.
    let displayID: Int

    private let screenFrame: NSRect

    static func displayID(of screen: NSScreen) -> Int {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? 0
    }

    init(screen: NSScreen, scrimOpacity: Double = 0.64) {
        displayID = Self.displayID(of: screen)
        screenFrame = screen.frame
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        // A picture, not a surface: a shadow derived from a nearly-transparent
        // full-screen alpha would outline the scrim itself (§8 deviation 0's rule,
        // applied to the one window whose content fades at every edge).
        hasShadow = false
        animationBehavior = .none
        ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: SnapOverlayView(model: model, screenFrame: screenFrame, scrimOpacity: scrimOpacity))
        hostingView.sizingOptions = []
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Live drag state, published so the panel's SwiftUI tree re-renders as the bar
/// moves without rebuilding the window.
final class SnapOverlayModel: ObservableObject {
    @Published var slots: [SnapZone: NSRect] = [:]
    @Published var active: SnapZone?
}

private struct SnapOverlayView: View {
    @ObservedObject var model: SnapOverlayModel
    let screenFrame: NSRect
    let scrimOpacity: Double

    var body: some View {
        ZStack {
            Color.black.opacity(scrimOpacity)

            ForEach(SnapZone.allCases, id: \.rawValue) { zone in
                slotShape(zone)
            }
        }
        .frame(
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    private func slotOutline(_ zone: SnapZone) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: zone == .left || zone == .topCenter ? 0 : 18,
            bottomLeadingRadius: zone == .left ? 0 : 18,
            bottomTrailingRadius: zone == .right ? 0 : 18,
            topTrailingRadius: zone == .right || zone == .topCenter ? 0 : 18
        )
    }

    @ViewBuilder
    private func slotShape(_ zone: SnapZone) -> some View {
        if let rect = model.slots[zone] {
            // AppKit screen coordinates are bottom-left origin; SwiftUI's are
            // top-left. The window covers exactly `screenFrame`, so the flip is one
            // subtraction and one origin shift.
            let flipped = CGRect(
                x: rect.minX - screenFrame.minX,
                y: screenFrame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            let active = model.active == zone
            slotOutline(zone)
                .fill(.white.opacity(active ? 0.38 : 0.18))
                .overlay {
                    slotOutline(zone)
                        .strokeBorder(.white.opacity(active ? 0.95 : 0.65),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .frame(width: flipped.width, height: flipped.height)
                .position(x: flipped.midX, y: flipped.midY)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: rect)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}
