import CoreGraphics
import Testing
@testable import ZonesCore

@Suite struct DragSnapTrackerTests {
  let start = CGPoint(x: 100, y: 100)
  let moved = CGPoint(x: 150, y: 120)

  @Test func shiftDragWithoutWindowMoveNeverShowsOverlay() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    for _ in 0..<5 { t.update(shiftHeld: true) { CGPoint(x: 100, y: 100) } }
    #expect(!t.overlayVisible); let snap = t.mouseUp(); #expect(!snap)
  }
  @Test func shiftDragWithMoveShowsOverlayAndSnaps() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { moved }
    #expect(t.overlayVisible); let snap = t.mouseUp(); #expect(snap)
  }
  @Test func shiftPressedMidDragWorks() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    for i in 1...3 { t.update(shiftHeld: false) { CGPoint(x: 100 + Double(i) * 20, y: 100) } }
    #expect(!t.overlayVisible)
    t.update(shiftHeld: true) { moved }
    #expect(t.overlayVisible)
  }
  @Test func releasingShiftHidesAndDropIsNormal() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { moved }
    t.update(shiftHeld: false) { moved }
    #expect(!t.overlayVisible); let snap = t.mouseUp(); #expect(!snap)
  }
  @Test func repressingShiftShowsAgain() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { moved }
    t.update(shiftHeld: false) { moved }
    t.update(shiftHeld: true) { moved }
    #expect(t.overlayVisible)
  }
  @Test func noWindowAtMouseDownNeverShows() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: nil)
    t.update(shiftHeld: true) { moved }
    #expect(!t.overlayVisible); let snap = t.mouseUp(); #expect(!snap)
  }
  @Test func flagsWithoutMouseDownNeverShow() {
    var t = DragSnapTracker()
    t.update(shiftHeld: true) { moved }
    #expect(!t.overlayVisible)
  }
  @Test func nilOriginMeansNotMovedYet() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { nil }
    #expect(!t.overlayVisible)
    t.update(shiftHeld: true) { moved }
    #expect(t.overlayVisible)
  }
  @Test func originNotQueriedWithoutShift() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    var calls = 0
    for _ in 0..<3 { t.update(shiftHeld: false) { calls += 1; return moved } }
    #expect(calls == 0)
  }
  @Test func originNotQueriedAfterMoveConfirmed() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { moved }
    var calls = 0
    for _ in 0..<3 { t.update(shiftHeld: true) { calls += 1; return moved } }
    #expect(calls == 0); #expect(t.overlayVisible)
  }
  @Test func mouseUpResets() {
    var t = DragSnapTracker(); t.mouseDown(windowOrigin: start)
    t.update(shiftHeld: true) { moved }
    _ = t.mouseUp()
    t.update(shiftHeld: true) { moved }
    #expect(!t.overlayVisible)
  }
}
