import CoreGraphics
import Foundation

/// The four fixed destinations. Raw values retain existing center/side preferences.
public enum SnapZone: String, CaseIterable, Codable, Sendable {
    case bottomCenter, topCenter, left, right

    public static func restored(from rawValue: String?) -> SnapZone {
        switch rawValue {
        case "topLeft", "topRight": return .topCenter
        case "bottomLeft", "bottomRight": return .bottomCenter
        default: return rawValue.flatMap(Self.init(rawValue:)) ?? .bottomCenter
        }
    }
}

/// Which side of the bar a taller thing grows into — the one decision every
/// above-anchored panel used to make on its own, in its own file, always answering
/// "above". `docs/bar-positioning.md`'s rule: whichever side has more room, so a
/// top-docked bar's result card hangs *below* it instead of being clamped back onto
/// the screen far from the bar.
public enum VerticalAnchorSide: Sendable {
    case above, below
}

/// How far a zone's slot sits from the work-area edge it touches. `bottom` is the
/// existing `bottomInset` (§4); `top` and `side` are its mirrors.
public struct BarSlotInsets: Sendable {
    public var bottom: CGFloat
    public var top: CGFloat
    public var side: CGFloat

    public init(bottom: CGFloat, top: CGFloat, side: CGFloat) {
        self.bottom = bottom
        self.top = top
        self.side = side
    }
}

/// Pure placement math for the overlay, testable without a window server — the same
/// reason `RewriteAttempt` lives in this package rather than in `App/`. Everything
/// here is a function of rectangles; `OverlayPlacement` is the AppKit glue that feeds
/// it `NSScreen`-derived work areas and persists its answers.
public enum BarPlacement {

    public static func attachedFrame(
        size: CGSize, zone: SnapZone, anchor: CGRect, workArea: CGRect
    ) -> CGRect {
        let size = CGSize(width: min(size.width, workArea.width),
                          height: min(size.height, workArea.height))
        var frame = CGRect(origin: .zero, size: size)
        switch zone {
        case .bottomCenter:
            frame.origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY)
        case .topCenter:
            frame.origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - size.height)
        case .left:
            frame.origin = CGPoint(x: anchor.minX, y: anchor.midY - size.height / 2)
        case .right:
            frame.origin = CGPoint(x: anchor.maxX - size.width, y: anchor.midY - size.height / 2)
        }
        return clamp(frame, to: workArea)
    }

    /// The resting frame a zone parks the bar at, for the bar's current size. Sized
    /// to the *current* size on purpose: a drag can start from the expanded row, and
    /// the slot the user is aiming at should be the size of the thing in their hand.
    public static func zoneFrame(
        _ zone: SnapZone,
        barSize: CGSize,
        workArea: CGRect,
        insets: BarSlotInsets,
        notch: CGRect? = nil
    ) -> CGRect {
        var frame = CGRect(origin: .zero, size: barSize)
        switch zone {
        case .bottomCenter:
            frame.origin.y = workArea.minY + insets.bottom
        case .topCenter:
            frame.origin.y = workArea.maxY - insets.top - barSize.height
        case .left, .right:
            frame.origin.y = workArea.midY - barSize.height / 2
        }
        switch zone {
        case .left:
            frame.origin.x = workArea.minX + insets.side
        case .right:
            frame.origin.x = workArea.maxX - insets.side - barSize.width
        case .bottomCenter, .topCenter:
            frame.origin.x = workArea.midX - barSize.width / 2
        }
        frame = clamp(frame, to: workArea)
        if zone == .topCenter, let notch {
            frame.origin.x = notch.midX - barSize.width / 2
            frame.origin.y = notch.minY - barSize.height
        }
        return frame
    }

    /// The nearby destination, or `nil` when the drag should return to its origin.
    ///
    /// Distance is the **gap between rectangles**, not between centres: a bar held
    /// directly over a slot is distance 0 however its size changed on the way, and a
    /// bar already resting in a slot reports 0 so a no-movement click-drag resolves
    /// to staying there. Ties keep the earlier case in `allCases` order — an exact
    /// tie is a symmetric position where either answer is defensible, and a stable
    /// one is the only requirement.
    public static func activeZone(
        near bar: CGRect,
        workArea: CGRect,
        insets: BarSlotInsets,
        edgeThreshold: CGFloat
    ) -> SnapZone? {
        let slots = Dictionary(uniqueKeysWithValues: SnapZone.allCases.map {
            ($0, zoneFrame($0, barSize: bar.size, workArea: workArea, insets: insets))
        })
        return activeZone(near: bar, slots: slots, threshold: edgeThreshold)
    }

    public static func activeZone(
        near bar: CGRect, slots: [SnapZone: CGRect], threshold: CGFloat
    ) -> SnapZone? {
        var best: (zone: SnapZone, distance: CGFloat)?
        for zone in SnapZone.allCases {
            guard let slot = slots[zone] else { continue }
            let distance = rectGap(from: bar, to: slot)
            guard distance <= threshold else { continue }
            if let best, distance >= best.distance { continue }
            best = (zone, distance)
        }
        return best?.zone
    }

    /// Zero when the rectangles touch or overlap, otherwise the shortest hop from one
    /// to the other — the gap that closing would have to travel.
    static func rectGap(from a: CGRect, to b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return hypot(dx, dy)
    }

    /// More room wins; a tie stays `.above` because that is the direction every panel
    /// already grew in before zones existed, so the default position never changes
    /// behaviour.
    public static func verticalSide(ofBar bar: CGRect, in workArea: CGRect) -> VerticalAnchorSide {
        let roomAbove = workArea.maxY - bar.maxY
        let roomBelow = bar.minY - workArea.minY
        return roomAbove >= roomBelow ? .above : .below
    }

    /// Where a panel that **replaces** the bar goes — the generating capsule and the
    /// result card (§4: they take the bar's place, they do not stack on it).
    ///
    /// The panel's outer edge lands on the bar's outer line and it grows through the
    /// strip the bar occupies, away from the edge: bottom-anchored keeps today's
    /// `y: bar.minY` exactly; top-anchored is its mirror with the **top** on
    /// `bar.maxY`. Side positions resolve by room, which keeps the panel
    /// attached to the bar instead of clamped away from it.
    public static func replaceFrame(size: CGSize, bar: CGRect, workArea: CGRect) -> CGRect {
        var frame = CGRect(origin: .zero, size: size)
        frame.origin.x = bar.midX - size.width / 2
        switch verticalSide(ofBar: bar, in: workArea) {
        case .above: frame.origin.y = bar.minY
        case .below: frame.origin.y = bar.maxY - size.height
        }
        return clamp(frame, to: workArea)
    }

    /// Where a panel that **stacks** beside another goes — the error toast, the reply
    /// context card, the update notice, the snooze menu: `gap` beyond the anchor's
    /// near edge, on the side with more room.
    ///
    /// The side is decided from the anchor's own frame, not from the bar's, so a
    /// toast raised over a result card answers about the card it will actually sit
    /// beside — and the whole stack points the same way without any panel knowing
    /// which one is underneath it.
    public static func stackedFrame(
        size: CGSize,
        gap: CGFloat,
        anchor: CGRect,
        workArea: CGRect
    ) -> CGRect {
        var frame = CGRect(origin: .zero, size: size)
        frame.origin.x = anchor.midX - size.width / 2
        switch verticalSide(ofBar: anchor, in: workArea) {
        case .above: frame.origin.y = anchor.maxY + gap
        case .below: frame.origin.y = anchor.minY - gap - size.height
        }
        return clamp(frame, to: workArea)
    }

    public static func stackedFrame(
        size: CGSize,
        gap: CGFloat,
        zone: SnapZone,
        anchor: CGRect,
        workArea: CGRect
    ) -> CGRect {
        let size = CGSize(width: min(size.width, workArea.width),
                          height: min(size.height, workArea.height))
        var frame = CGRect(x: anchor.midX - size.width / 2,
                           y: anchor.midY - size.height / 2,
                           width: size.width, height: size.height)
        switch zone {
        case .bottomCenter: frame.origin.y = anchor.maxY + gap
        case .topCenter: frame.origin.y = anchor.minY - gap - size.height
        case .left: frame.origin.x = anchor.maxX + gap
        case .right: frame.origin.x = anchor.minX - gap - size.width
        }
        return clamp(frame, to: workArea)
    }

    /// Same formula `OverlayPlacement` has always used, kept byte-identical so the
    /// package's answer never diverges from the AppKit glue by a rounding step.
    public static func clamp(_ rect: CGRect, to area: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.origin.x, area.minX), area.maxX - rect.width)
        result.origin.y = min(max(rect.origin.y, area.minY), area.maxY - rect.height)
        return result
    }
}
