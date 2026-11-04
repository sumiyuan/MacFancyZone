import CoreGraphics
import Foundation

public enum EditorHit: Equatable, Sendable {
    case divider(Divider)
    case zone(path: NodePath, local: CGPoint)   // local = fraction within the zone, 0...1 each axis
    case none
}

public enum EditorHitTest {
    public static let dividerTolerance: CGFloat = 6   // points, measured perpendicular to the line

    /// point is in points, top-left origin, relative to a canvas of `size` (the visible frame).
    public static func hit(_ point: CGPoint, layout: LayoutNode, canvasSize: CGSize) -> EditorHit {
        guard canvasSize.width > 0, canvasSize.height > 0,
              point.x >= 0, point.y >= 0,
              point.x <= canvasSize.width, point.y <= canvasSize.height else { return .none }
        let ux = Double(point.x / canvasSize.width)
        let uy = Double(point.y / canvasSize.height)

        var best: (distance: Double, divider: Divider)?
        for divider in layout.dividers() {
            let along: Double, cross: Double, scale: Double
            switch divider.direction {
            case .vertical: along = ux; cross = uy; scale = Double(canvasSize.width)
            case .horizontal: along = uy; cross = ux; scale = Double(canvasSize.height)
            }
            guard cross >= divider.crossStart, cross <= divider.crossStart + divider.crossSpan else { continue }
            let distance = abs(along - divider.position) * scale
            guard distance <= Double(dividerTolerance) else { continue }
            if best == nil || distance < best!.distance { best = (distance, divider) }
        }
        if let best { return .divider(best.divider) }

        for zone in layout.zones() {
            let r = zone.unitRect
            guard ux >= r.minX, ux <= r.maxX, uy >= r.minY, uy <= r.maxY else { continue }
            return .zone(path: zone.path,
                         local: CGPoint(x: (ux - r.minX) / r.width, y: (uy - r.minY) / r.height))
        }
        return .none
    }

    /// New ratio for a divider being dragged to `point`, clamped to LayoutNode.ratioRange.
    public static func ratio(dragging: Divider, to point: CGPoint, canvasSize: CGSize) -> Double {
        let f: Double
        switch dragging.direction {
        case .vertical: f = Double(point.x / canvasSize.width)
        case .horizontal: f = Double(point.y / canvasSize.height)
        }
        let r = (f - dragging.start) / dragging.span
        return min(max(r, LayoutNode.ratioRange.lowerBound), LayoutNode.ratioRange.upperBound)
    }
}
