import CoreGraphics
import Foundation

public enum ZoneGeometry {
    private static let edgeEpsilon = 1e-9

    /// `frame` is a visible frame in top-left global coordinates (AX/CG space). Returned in zone-number order.
    public static func zoneRects(for layout: LayoutNode, in frame: CGRect, spacing: Double, outerGap: Bool) -> [CGRect] {
        let s = CGFloat(spacing)
        let container = outerGap ? frame.insetBy(dx: s, dy: s) : frame
        let half = s / 2
        return layout.zones().map { zone in
            let u = zone.unitRect
            let minX = container.minX + u.minX * container.width
            let maxX = container.minX + u.maxX * container.width
            let minY = container.minY + u.minY * container.height
            let maxY = container.minY + u.maxY * container.height
            let left = abs(u.minX) < edgeEpsilon ? 0 : half
            let right = abs(u.maxX - 1) < edgeEpsilon ? 0 : half
            let top = abs(u.minY) < edgeEpsilon ? 0 : half
            let bottom = abs(u.maxY - 1) < edgeEpsilon ? 0 : half
            return CGRect(x: minX + left, y: minY + top,
                          width: max(0, maxX - minX - left - right),
                          height: max(0, maxY - minY - top - bottom))
        }
    }

    /// AppKit (bottom-left, primary-screen-relative) <-> AX/CG (top-left). It undoes itself.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flipped(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Hit test against gapless rects, so a cursor in a gap still picks a zone. Returns a 0-based index.
    public static func zoneIndex(at point: CGPoint, layout: LayoutNode, in frame: CGRect) -> Int? {
        guard point.x >= frame.minX, point.x <= frame.maxX,
              point.y >= frame.minY, point.y <= frame.maxY else { return nil }
        let rects = zoneRects(for: layout, in: frame, spacing: 0, outerGap: false)
        return rects.firstIndex { $0.minX <= point.x && point.x <= $0.maxX && $0.minY <= point.y && point.y <= $0.maxY }
    }
}
