import Testing
@testable import SwitcherCore

@Suite struct RecencyOrderingTests {
    private func cand(_ k: String, _ pid: Int32) -> WindowCandidate<String> {
        WindowCandidate(key: k, appPID: pid)
    }

    @Test func touchMovesToFront() {
        var l = RecencyList<String>()
        l.touch("a"); l.touch("b"); l.touch("a")
        #expect(l.items == ["a", "b"])
        #expect(l.rank(of: "b") == 1)
        #expect(l.rank(of: "z") == nil)
    }

    @Test func pruneDropsClosedWindows() {
        var l = RecencyList<String>()
        l.touch("c"); l.touch("b"); l.touch("a")
        l.prune(keeping: ["a", "c"])
        #expect(l.items == ["a", "c"])
    }

    @Test func capacityDropsOldest() {
        var l = RecencyList<String>(capacity: 3)
        l.touch("a"); l.touch("b"); l.touch("c"); l.touch("d")
        #expect(l.items == ["d", "c", "b"])
        l.touch("b")
        #expect(l.items == ["b", "d", "c"])
    }

    @Test func removeDropsOneKey() {
        var l = RecencyList<String>()
        l.touch("a"); l.touch("b"); l.touch("c")
        l.remove("b")
        #expect(l.items == ["c", "a"])
    }

    @Test func trackedWindowsComeFirstByRecency() {
        var w = RecencyList<String>()
        w.touch("w3"); w.touch("w2")
        let out = RecencyOrdering.order([cand("w1", 1), cand("w2", 1), cand("w3", 2)],
                                        windows: w, apps: RecencyList<Int32>())
        #expect(out == ["w2", "w3", "w1"])
    }

    @Test func untrackedWindowsFollowAppRecency() {
        var a = RecencyList<Int32>()
        a.touch(1); a.touch(2)
        let out = RecencyOrdering.order([cand("w1", 1), cand("w2", 2), cand("w3", 1)],
                                        windows: RecencyList<String>(), apps: a)
        #expect(out == ["w2", "w1", "w3"])
    }

    @Test func unknownAppsGoLastInEnumerationOrder() {
        var a = RecencyList<Int32>()
        a.touch(2)
        let out = RecencyOrdering.order([cand("w1", 9), cand("w2", 2), cand("w3", 8)],
                                        windows: RecencyList<String>(), apps: a)
        #expect(out == ["w2", "w1", "w3"])
    }

    @Test func candidatesNotPresentAreNeverReturned() {
        var w = RecencyList<String>()
        w.touch("gone"); w.touch("w1")
        let out = RecencyOrdering.order([cand("w1", 1), cand("w2", 1)],
                                        windows: w, apps: RecencyList<Int32>())
        #expect(out == ["w1", "w2"])
    }
}
