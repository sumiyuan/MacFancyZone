import Foundation
import Testing
@testable import MixerCore

@Test func neutralIsNotCaptured() {
    #expect(!AppAudioSetting.neutral.needsCapture)
    #expect(AppAudioSetting.neutral.gain == 1)
}

@Test func mutedGainIsZeroAndCaptured() {
    let s = AppAudioSetting(volume: 0.4, muted: true)
    #expect(s.gain == 0)
    #expect(s.needsCapture)
}

@Test func boostedIsCaptured() {
    #expect(AppAudioSetting(volume: 1.5, muted: false).needsCapture)
}

@Test func clampsOutOfRangeVolume() throws {
    #expect(AppAudioSetting(volume: 3, muted: false).volume == 1.5)
    #expect(AppAudioSetting(volume: -1, muted: false).volume == 0)
    let json = Data(#"{"apps":{"a":{"volume":9,"muted":false}}}"#.utf8)
    #expect(try JSONDecoder().decode(MixerSettings.self, from: json).setting(for: "a").volume == 1.5)
}

@Test func unknownAppIsNeutral() {
    #expect(MixerSettings().setting(for: "x") == .neutral)
}

@Test func setVolumeUnmutes() {
    var m = MixerSettings()
    m.setMuted(true, for: "a")
    m.setVolume(0.4, for: "a")
    #expect(m.setting(for: "a") == AppAudioSetting(volume: 0.4, muted: false))
}

@Test func unmuteRestoresVolume() {
    var m = MixerSettings()
    m.setVolume(0.4, for: "a")
    m.setMuted(true, for: "a")
    m.setMuted(false, for: "a")
    #expect(m.setting(for: "a").volume == 0.4)
}

@Test func neutralEntriesAreDropped() {
    var m = MixerSettings()
    m.setVolume(0.5, for: "a")
    m.setVolume(1.0, for: "a")
    #expect(m.apps.isEmpty)
}

@Test func decodesMalformedFileAsEmpty() throws {
    let json = Data(#"{"apps":{"a":{"volume":"loud"},"b":{"volume":0.5,"muted":true}}}"#.utf8)
    let m = try JSONDecoder().decode(MixerSettings.self, from: json)
    #expect(m.apps.keys.sorted() == ["b"])
    let notObject = Data(#"{"apps":[1,2]}"#.utf8)
    #expect(try JSONDecoder().decode(MixerSettings.self, from: notObject) == MixerSettings())
}

@Test func storeRoundTripsAndToleratesGarbage() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = MixerStore(directory: dir)
    #expect(store.load() == MixerSettings())
    var m = MixerSettings()
    m.setVolume(0.25, for: "com.spotify.client")
    try store.save(m)
    #expect(store.load() == m)
    try Data("not json".utf8).write(to: dir.appendingPathComponent("mixer.json"))
    #expect(store.load() == MixerSettings())
}
