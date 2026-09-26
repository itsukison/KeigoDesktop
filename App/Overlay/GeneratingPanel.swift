import AppKit
import BorderBeamKit
import DesktopRewriteKit
import SwiftUI

final class GeneratingPanel: NSPanel {
    private let geometry: CurrentValueBox<CompanionGeometry>

    init(geometry: CompanionGeometry, label: String, onCancel: @escaping () -> Void) {
        self.geometry = CurrentValueBox(geometry)
        super.init(contentRect: geometry.generationWindowFrame,
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        // Native shadows trace the bloom's alpha envelope and leave a detached dark ring.
        hasShadow = false
        animationBehavior = .none
        let host = NSHostingView(rootView: GeneratingPanelContent(geometry: self.geometry, label: label, onCancel: onCancel))
        host.sizingOptions = []
        contentView = host
    }

    func reanchor(_ geometry: CompanionGeometry) {
        self.geometry.value = geometry
        setFrame(geometry.generationWindowFrame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct GeneratingPanelContent: View {
    @ObservedObject var geometry: CurrentValueBox<CompanionGeometry>
    let label: String
    let onCancel: () -> Void

    var body: some View {
        GeneratingCapsule(label: label, zone: geometry.value.zone,
                          size: geometry.value.generationSize, onCancel: onCancel)
    }
}

extension CompanionGeometry {
    var generationWindowFrame: NSRect {
        let visible = frame(size: generationSize)
        let padding = zone.generationPadding
        return NSRect(x: visible.minX - padding.leading, y: visible.minY - padding.bottom,
                      width: visible.width + padding.leading + padding.trailing,
                      height: visible.height + padding.top + padding.bottom)
    }
}

private extension SnapZone {
    var generationPadding: EdgeInsets {
        let spread = Tokens.Geometry.generatingGlowSpread
        switch self {
        case .bottomCenter:
            return EdgeInsets(top: spread, leading: spread, bottom: Tokens.Geometry.generatingGlowPadding, trailing: spread)
        case .topCenter: return EdgeInsets(top: 0, leading: spread, bottom: spread, trailing: spread)
        case .left: return EdgeInsets(top: spread, leading: 0, bottom: spread, trailing: spread)
        case .right: return EdgeInsets(top: spread, leading: spread, bottom: spread, trailing: 0)
        }
    }
}

struct GeneratingCapsule: View {
    let label: String
    var zone: SnapZone = .bottomCenter
    var size = NSSize(width: 176, height: 36)
    var forceReducedMotion = false
    var forceOpaque = false
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var padding: EdgeInsets { zone.generationPadding }
    private var shape: UnevenRoundedRectangle { zone.companionShape(generating: true) }
    private var windowSize: NSSize {
        NSSize(width: size.width + padding.leading + padding.trailing,
               height: size.height + padding.top + padding.bottom)
    }

    var body: some View {
        ZStack {
            SmokedGlassSurface(shape: shape, joinsNotch: zone == .topCenter, forceOpaque: forceOpaque)
                .frame(width: size.width, height: size.height)
                .padding(padding)

            activity
                .frame(width: size.width, height: size.height)
                .padding(padding)
                .mask {
                    Rectangle().fill(edgeFade(length: windowSize.height, horizontal: false))
                        .mask(Rectangle().fill(edgeFade(length: windowSize.width, horizontal: true)))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                MascotSprite(animation: .thinking, isAnimating: !(reduceMotion || forceReducedMotion))
                Text(label)
                    .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .lineLimit(zone == .left || zone == .right ? 2 : 1)
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tokens.Overlay.textSecondary)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .accessibilityLabel(tr("キャンセル", "Cancel", "取消"))
            }
            .padding(.horizontal, 14)
            .frame(width: size.width, height: size.height)
            .padding(padding)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .opacity(appeared ? 1 : 0.85)
        .onAppear {
            withAnimation(reduceMotion || forceReducedMotion ? nil : .easeOut(duration: 0.14)) { appeared = true }
        }
    }

    private var activity: some View {
        // Extend the rounded beam beyond the attached edge. Its hidden edge/corners
        // stay outside the window, while the exposed outline matches the surface.
        let extensionLength: CGFloat = zone == .bottomCenter ? 0 : 48
        let horizontal = zone == .left || zone == .right
        let beamWidth = size.width + (horizontal ? extensionLength : 0)
        let beamHeight = size.height + (zone == .topCenter ? extensionLength : 0)
        let radius: CGFloat = zone == .topCenter ? 8 : 18
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Color(hex: 0xff6b8a), Color(hex: 0xffbe62), Color(hex: 0xf6ed79),
                             Color(hex: 0x75e5b0), Color(hex: 0x5de1ff), Color(hex: 0x9b8aff),
                             Color(hex: 0xec8fff)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ).opacity(0.85), lineWidth: 1.5)
            if !(reduceMotion || forceReducedMotion) {
                BorderBeam(size: .md, colorVariant: .colorful, theme: .dark,
                           duration: 3.6, borderRadius: radius, brightness: 1.8,
                           saturation: 1.5, hueRange: 0, strength: 1) { Color.clear }
            }
        }
        .frame(width: beamWidth, height: beamHeight)
        .offset(x: zone == .left ? -extensionLength / 2 : zone == .right ? extensionLength / 2 : 0,
                y: zone == .topCenter ? -extensionLength / 2 : 0)
    }

    private func edgeFade(length: CGFloat, horizontal: Bool) -> LinearGradient {
        let stop = min(4 / max(length, 1), 0.5)
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .white, location: stop),
            .init(color: .white, location: 1 - stop),
            .init(color: .clear, location: 1)
        ], startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom)
    }
}
