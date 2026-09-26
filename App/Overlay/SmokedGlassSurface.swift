import AppKit
import SwiftUI

struct SmokedGlassSurface<S: InsettableShape>: View {
    let shape: S
    var joinsNotch = false
    var forceOpaque = false
    var showsBorder = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if joinsNotch {
                shape.fill(Color.black)
            } else if forceOpaque || reduceTransparency || contrast == .increased {
                shape.fill(Color(hex: 0x17191b))
                    .overlay {
                        if showsBorder {
                            shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.45 : 0.14), lineWidth: 1)
                        }
                    }
            } else {
                shape.fill(LinearGradient(
                    colors: [Color(hex: 0x22292b).opacity(0.78), Color(hex: 0x131719).opacity(0.84)],
                    startPoint: .top, endPoint: .bottom
                ))
                    .background { SoftGlassBackdrop(shape: shape) }
                    .overlay {
                        if showsBorder {
                            shape.strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.06), .black.opacity(0.25)],
                                startPoint: .top, endPoint: .bottom
                            ), lineWidth: 1)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SoftGlassBackdrop<S: Shape>: NSViewRepresentable {
    let shape: S

    func makeNSView(context: Context) -> BackdropView<S> {
        let view = BackdropView(shape: shape)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.alphaValue = Tokens.Overlay.glassBlurBlend
        return view
    }

    func updateNSView(_ view: BackdropView<S>, context: Context) {
        view.shape = shape
        view.alphaValue = Tokens.Overlay.glassBlurBlend
        view.needsLayout = true
    }
}

private final class BackdropView<S: Shape>: NSVisualEffectView {
    var shape: S
    private let shapeMask = CAShapeLayer()

    init(shape: S) {
        self.shape = shape
        super.init(frame: .zero)
        wantsLayer = true
        layer?.mask = shapeMask
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = shape.path(in: bounds).cgPath
        CATransaction.commit()
    }
}
