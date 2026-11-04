import CoreGraphics
import Foundation
import Testing
@testable import ZonesCore

private func threeColumns() -> LayoutNode {
    LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.5)!
        .splitting(zoneAt: [.second], direction: .vertical, ratio: 0.5)!
}

@Test func singleZoneCoversUnitSquare() {
    #expect(LayoutNode.zone.zones() == [Zone(number: 1, path: [], unitRect: CGRect(x: 0, y: 0, width: 1, height: 1))])
}

@Test func threeColumnsNumberLeftToRight() {
    let l = threeColumns()
    #expect(l.zones().map(\.number) == [1, 2, 3])
    #expect(l.zones().map(\.unitRect.minX) == [0, 0.5, 0.75])
}

@Test func horizontalSplitStacks() {
    let l = LayoutNode.zone.splitting(zoneAt: [], direction: .horizontal, ratio: 0.25)!
    #expect(l.zones()[1].unitRect == CGRect(x: 0, y: 0.25, width: 1, height: 0.75))
}

@Test func splitOutsideRatioRangeIsRejected() {
    #expect(LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.03) == nil)
    #expect(LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.97) == nil)
}

@Test func splittingASplitIsRejected() {
    #expect(threeColumns().splitting(zoneAt: [], direction: .horizontal, ratio: 0.5) == nil)
    #expect(threeColumns().splitting(zoneAt: [.second], direction: .horizontal, ratio: 0.5) == nil)
}

@Test func resizeClampsRatio() {
    let l = LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.5)!
    #expect(l.resizing(splitAt: [], ratio: 1.4) == .split(direction: .vertical, ratio: 0.95, first: .zone, second: .zone))
    #expect(l.resizing(splitAt: [.first], ratio: 0.3) == nil)
}

@Test func removeDividerMergesTwoPlainZones() {
    let l = LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.5)!
    #expect(l.removingDivider(at: []) == .zone)
}

@Test func removeDividerWithSplitChildIsRejected() {
    let l = threeColumns()
    #expect(l.removingDivider(at: []) == nil)
    #expect(l.removingDivider(at: [.second]) == LayoutNode.zone.splitting(zoneAt: [], direction: .vertical, ratio: 0.5))
}

@Test func dividerGeometryForNestedSplit() {
    let d = threeColumns().dividers().first { $0.path == [.second] }!
    #expect(d.direction == .vertical)
    #expect(d.position == 0.75)
    #expect(d.start == 0.5)
    #expect(d.span == 0.5)
    #expect(d.crossStart == 0)
    #expect(d.crossSpan == 1)
}

@Test func codableRoundTrip() throws {
    let l = threeColumns()
    let data = try JSONEncoder().encode(l)
    #expect(try JSONDecoder().decode(LayoutNode.self, from: data) == l)
}

@Test func sanitizedClampsRatios() {
    let l = LayoutNode.split(direction: .vertical, ratio: 2, first: .zone, second: .zone)
    #expect(l.sanitized() == .split(direction: .vertical, ratio: 0.95, first: .zone, second: .zone))
}
