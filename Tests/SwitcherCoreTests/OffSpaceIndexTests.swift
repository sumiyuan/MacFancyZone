import Foundation
import Testing
@testable import SwitcherCore

@Test func remoteTokenLayout() {
    let data = RemoteToken.data(pid: 0x01020304, elementID: 0x1122334455667788)
    #expect(data.count == 20)
    #expect(Array(data) == [0x04, 0x03, 0x02, 0x01,  0, 0, 0, 0,  0x6f, 0x63, 0x6f, 0x63,
                            0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
}

@Test func unknownWindowsNeedScan() {
    let index = OffSpaceIndex<String>()
    #expect(index.missing(pid: 5, systemWindowIDs: [1, 2, 3], visibleIDs: [1]) == [2, 3])
}

@Test func resolvedAndRejectedWindowsDoNotNeedScan() {
    var index = OffSpaceIndex<String>()
    index.recordScan(pid: 5, looked: [2, 3, 4], found: [2: "two"])
    #expect(index.missing(pid: 5, systemWindowIDs: [1, 2, 3, 4], visibleIDs: [1]).isEmpty)
    #expect(index.offDesktop(pid: 5, visibleIDs: [1]) == [2: "two"])
}

@Test func closedWindowsAreForgotten() {
    var index = OffSpaceIndex<String>()
    index.recordScan(pid: 5, looked: [2, 3], found: [2: "two", 3: "three"])
    index.prune(pid: 5, systemWindowIDs: [3])
    #expect(index.offDesktop(pid: 5, visibleIDs: []) == [3: "three"])
}

@Test func newWindowAfterScanNeedsScan() {
    var index = OffSpaceIndex<String>()
    index.recordScan(pid: 5, looked: [2], found: [2: "two"])
    #expect(index.missing(pid: 5, systemWindowIDs: [2, 9], visibleIDs: []) == [9])
}

@Test func quitAppIsForgotten() {
    var index = OffSpaceIndex<String>()
    index.recordScan(pid: 5, looked: [2], found: [2: "two"])
    index.retain(pids: [6])
    #expect(index.offDesktop(pid: 5, visibleIDs: []).isEmpty)
}

// The reported bug: a window found on another desktop, visited, then left again.
@Test func visitedWindowReturnsWhenLeftAgain() {
    var index = OffSpaceIndex<String>()
    index.recordScan(pid: 5, looked: [2], found: [2: "full screen"])
    #expect(index.offDesktop(pid: 5, visibleIDs: [2]).isEmpty)          // visiting it
    #expect(index.offDesktop(pid: 5, visibleIDs: []) == [2: "full screen"]) // left again
}

@Test func windowSeenHereIsKnownWhenMovedAway() {
    var index = OffSpaceIndex<String>()
    index.remember(pid: 5, id: 7, element: "here")
    #expect(index.missing(pid: 5, systemWindowIDs: [7], visibleIDs: []).isEmpty)
    #expect(index.offDesktop(pid: 5, visibleIDs: []) == [7: "here"])
}
