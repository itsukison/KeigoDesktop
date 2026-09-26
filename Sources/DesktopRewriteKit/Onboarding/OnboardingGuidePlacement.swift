import Foundation

public enum OnboardingGuidePlacement {
    public enum Edge: CaseIterable, Sendable { case above, below, left, right }
    public struct Placement: Equatable, Sendable {
        public let frame: CGRect
        public let edge: Edge
    }

    public static func place(target: CGRect, owner: CGRect, size: CGSize, workArea: CGRect,
                             preferred: Edge, obstacles: [CGRect]) -> Placement? {
        let area = workArea.insetBy(dx: 8, dy: 8)
        guard size.width <= area.width, size.height <= area.height else { return nil }
        let edges = [preferred] + Edge.allCases.filter { $0 != preferred }
        for edge in edges {
            var origin: CGPoint
            switch edge {
            case .above: origin = CGPoint(x: target.midX - size.width / 2, y: owner.maxY + 10)
            case .below: origin = CGPoint(x: target.midX - size.width / 2, y: owner.minY - size.height - 10)
            case .left: origin = CGPoint(x: owner.minX - size.width - 10, y: target.midY - size.height / 2)
            case .right: origin = CGPoint(x: owner.maxX + 10, y: target.midY - size.height / 2)
            }
            origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
            origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
            let frame = CGRect(origin: origin, size: size)
            guard !frame.intersects(owner), !obstacles.contains(where: { frame.intersects($0) }) else { continue }
            return Placement(frame: frame, edge: edge)
        }
        return nil
    }
}
