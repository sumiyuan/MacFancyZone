import CoreGraphics
import Testing
@testable import ZonesCore

private let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let twoCols = LayoutNode.split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone)

@Test func twoColumnsWithOuterGap() {
    #expect(ZoneGeometry.zoneRects(for: twoCols, in: frame, spacing: 8, outerGap: true)
            == [CGRect(x: 8, y: 8, width: 488, height: 784), CGRect(x: 504, y: 8, width: 488, height: 784)])
}

@Test func twoColumnsWithoutOuterGap() {
    #expect(ZoneGeometry.zoneRects(for: twoCols, in: frame, spacing: 8, outerGap: false)
            == [CGRect(x: 0, y: 0, width: 496, height: 800), CGRect(x: 504, y: 0, width: 496, height: 800)])
}

@Test func zeroSpacingTilesExactly() {
    let layout = LayoutNode.split(direction: .vertical, ratio: 0.25, first: .zone,
        second: .split(direction: .horizontal, ratio: 0.5, first: .zone, second: .zone))
    let rects = ZoneGeometry.zoneRects(for: layout, in: frame, spacing: 0, outerGap: true)
    #expect(rects.count == 3)
    #expect(rects.reduce(rects[0]) { $0.union($1) } == frame)
    let area = rects.reduce(0.0) { $0 + $1.width * $1.height }
    #expect(abs(area - frame.width * frame.height) < 1e-6)
    for i in rects.indices { for j in rects.indices where i < j {
        let inter = rects[i].intersection(rects[j])
        #expect(inter.isNull || inter.width * inter.height < 1e-9)
    } }
}

@Test func offsetFrameIsRespected() {
    let f = CGRect(x: 1440, y: 25, width: 1000, height: 800)
    let base = ZoneGeometry.zoneRects(for: twoCols, in: frame, spacing: 8, outerGap: true)
    let moved = ZoneGeometry.zoneRects(for: twoCols, in: f, spacing: 8, outerGap: true)
    #expect(moved == base.map { $0.offsetBy(dx: 1440, dy: 25) })
}

@Test func flipPrimaryVisibleFrame() {
    #expect(ZoneGeometry.flipped(CGRect(x: 0, y: 50, width: 1440, height: 825), primaryScreenHeight: 900)
            == CGRect(x: 0, y: 25, width: 1440, height: 825))
}

@Test func flipSecondaryScreenLeftAndBelow() {
    #expect(ZoneGeometry.flipped(CGRect(x: -1920, y: -200, width: 1920, height: 1080), primaryScreenHeight: 900)
            == CGRect(x: -1920, y: 20, width: 1920, height: 1080))
}

@Test func flipIsAnInvolution() {
    let r = CGRect(x: 12, y: 34, width: 56, height: 78)
    #expect(ZoneGeometry.flipped(ZoneGeometry.flipped(r, primaryScreenHeight: 900), primaryScreenHeight: 900) == r)
    let p = CGPoint(x: 5, y: 7)
    #expect(ZoneGeometry.flipped(ZoneGeometry.flipped(p, primaryScreenHeight: 900), primaryScreenHeight: 900) == p)
}

@Test func hitTestInGapPicksNearestZone() {
    let i = ZoneGeometry.zoneIndex(at: CGPoint(x: 500, y: 400), layout: twoCols, in: frame)
    #expect(i == 0 || i == 1)
    #expect(ZoneGeometry.zoneIndex(at: CGPoint(x: 100, y: 400), layout: twoCols, in: frame) == 0)
    #expect(ZoneGeometry.zoneIndex(at: CGPoint(x: 900, y: 400), layout: twoCols, in: frame) == 1)
    #expect(ZoneGeometry.zoneIndex(at: CGPoint(x: 1000, y: 800), layout: twoCols, in: frame) == 1)
}

@Test func hitTestOutsideFrameIsNil() {
    #expect(ZoneGeometry.zoneIndex(at: CGPoint(x: 1200, y: 400), layout: twoCols, in: frame) == nil)
}

@Test func hugeSpacingNeverProducesNegativeSizes() {
    let row = LayoutNode.split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone)
    let layout = LayoutNode.split(direction: .horizontal, ratio: 0.5,
        first: .split(direction: .vertical, ratio: 0.5, first: row, second: row),
        second: .split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone))
    let f = CGRect(x: 0, y: 0, width: 300, height: 200)
    let rects = ZoneGeometry.zoneRects(for: layout, in: f, spacing: 64, outerGap: true)
    #expect(rects.count == 6)
    for r in rects { #expect(r.width >= 0 && r.height >= 0) }
}
