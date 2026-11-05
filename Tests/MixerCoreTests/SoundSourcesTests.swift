import Testing
@testable import MixerCore

private let yt = OwningApp(bundleID: "com.github.Electron", name: "Electron", pid: 100)
private let spotify = OwningApp(bundleID: "com.spotify.client", name: "Spotify", pid: 200)
private func owner(_ pid: Int32) -> OwningApp? { [100: yt, 101: yt, 102: yt, 200: spotify][pid] }

@Test func resolveWalksParentChain() {
    let parents: [Int32: Int32] = [102: 101, 101: 100, 100: 1]
    #expect(resolveOwner(pid: 102, parent: { parents[$0] }, app: { $0 == 100 ? yt : nil }) == yt)
}

@Test func resolveGivesUpAtLaunchd() {
    #expect(resolveOwner(pid: 50, parent: { _ in 1 }, app: { _ in nil }) == nil)
}

@Test func resolveGivesUpOnCycle() {
    #expect(resolveOwner(pid: 50, parent: { $0 == 50 ? 51 : 50 }, app: { _ in nil }) == nil)
}

@Test func groupsHelpersUnderOwningApp() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 1, pid: 101, isPlaying: true),
                         .init(objectID: 2, pid: 102, isPlaying: false)], owner: owner, now: 0)
    #expect(s.rows == [yt])
    #expect(s.processObjects(for: yt.bundleID).sorted() == [1, 2])
}

@Test func quietAppsAreNotListed() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: false)], owner: owner, now: 0)
    #expect(s.rows.isEmpty)
}

@Test func rowLingersFiveSeconds() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: true)], owner: owner, now: 0)
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: false)], owner: owner, now: 4.9)
    #expect(s.rows == [spotify])
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: false)], owner: owner, now: 5.1)
    #expect(s.rows.isEmpty)
}

@Test func rowsSortedByName() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: true),
                         .init(objectID: 2, pid: 100, isPlaying: true)], owner: owner, now: 0)
    #expect(s.rows.map(\.name) == ["Electron", "Spotify"])
}

@Test func untraceableProcessIgnored() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 9, pid: 999, isPlaying: true)], owner: owner, now: 0)
    #expect(s.rows.isEmpty)
}

@Test func isPlayingReflectsLatestUpdate() {
    var s = SoundSources()
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: true)], owner: owner, now: 0)
    #expect(s.isPlaying(spotify.bundleID))
    s.update(processes: [.init(objectID: 1, pid: 200, isPlaying: false)], owner: owner, now: 1)
    #expect(!s.isPlaying(spotify.bundleID))
}
