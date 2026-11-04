import Testing
import CoreGraphics
@testable import ZonesCore

@Suite struct EditorHitTestTests {
    let size = CGSize(width: 1000, height: 800)
    let twoColumns = LayoutNode.split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone)

    @Test func pointNearDividerHitsDivider() {
        guard case let .divider(d) = EditorHitTest.hit(CGPoint(x: 503, y: 400), layout: twoColumns, canvasSize: size) else {
            Issue.record("expected divider"); return
        }
        #expect(d.path == [])
    }

    @Test func pointInZoneGivesLocalFraction() {
        let hit = EditorHitTest.hit(CGPoint(x: 250, y: 200), layout: twoColumns, canvasSize: size)
        guard case let .zone(path, local) = hit else { Issue.record("expected zone"); return }
        #expect(path == [.first])
        #expect(abs(local.x - 0.5) < 1e-9)
        #expect(abs(local.y - 0.25) < 1e-9)
    }

    @Test func pointOutsideCanvasIsNone() {
        #expect(EditorHitTest.hit(CGPoint(x: -1, y: 10), layout: twoColumns, canvasSize: size) == .none)
        #expect(EditorHitTest.hit(CGPoint(x: 500, y: 801), layout: twoColumns, canvasSize: size) == .none)
        #expect(EditorHitTest.hit(CGPoint(x: 1001, y: 10), layout: twoColumns, canvasSize: size) == .none)
    }

    @Test func dividerOnlyHitWithinItsCrossExtent() {
        let layout = LayoutNode.split(direction: .vertical, ratio: 0.5, first: .zone,
                                      second: .split(direction: .horizontal, ratio: 0.5, first: .zone, second: .zone))
        // Horizontal divider at y = 400 spans x 500...1000 only.
        guard case .zone(let path, _) = EditorHitTest.hit(CGPoint(x: 250, y: 400), layout: layout, canvasSize: size) else {
            Issue.record("expected zone"); return
        }
        #expect(path == [.first])
        guard case let .divider(d) = EditorHitTest.hit(CGPoint(x: 750, y: 402), layout: layout, canvasSize: size) else {
            Issue.record("expected divider"); return
        }
        #expect(d.path == [.second])
    }

    @Test func dragRatioIsRelativeToParent() {
        let layout = LayoutNode.split(direction: .vertical, ratio: 0.5, first: .zone,
                                      second: .split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone))
        let inner = layout.dividers().first { $0.path == [.second] }!
        let r = EditorHitTest.ratio(dragging: inner, to: CGPoint(x: 900, y: 10), canvasSize: size)
        #expect(abs(r - 0.8) < 1e-9)
    }

    @Test func dragRatioClamps() {
        let d = twoColumns.dividers()[0]
        #expect(EditorHitTest.ratio(dragging: d, to: CGPoint(x: -50, y: 0), canvasSize: size) == 0.05)
        #expect(EditorHitTest.ratio(dragging: d, to: CGPoint(x: 5000, y: 0), canvasSize: size) == 0.95)
    }
}
