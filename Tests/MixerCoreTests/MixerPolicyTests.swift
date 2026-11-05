import Testing
@testable import MixerCore

private let quiet = AppAudioSetting(volume: 0.4, muted: false)

@Test func noCaptureWithoutProcesses() {
    let p = MixerPolicy()
    #expect(!p.shouldCapture("a", setting: quiet, processCount: 0))
    #expect(p.shouldCapture("a", setting: quiet, processCount: 1))
    #expect(!p.shouldCapture("a", setting: .neutral, processCount: 1))
}

@Test func setupFailureRetriesBeforeGivingUp() {
    var p = MixerPolicy()
    p.setupFailed("a"); p.setupFailed("a")
    #expect(p.shouldCapture("a", setting: quiet, processCount: 1))
    p.setupFailed("a")
    #expect(!p.shouldCapture("a", setting: quiet, processCount: 1))
    #expect(p.gaveUp("a"))
    p.resetFailures()
    #expect(p.shouldCapture("a", setting: quiet, processCount: 1))
}

@Test func setupSuccessClearsFailures() {
    var p = MixerPolicy()
    p.setupFailed("a"); p.setupFailed("a"); p.setupSucceeded("a"); p.setupFailed("a")
    #expect(!p.gaveUp("a"))
}

@Test func silenceBeforePermissionConfirmedGivesUpAndWarns() {
    var p = MixerPolicy()
    #expect(p.respond(to: .silent, for: "a") == .giveUp)
    #expect(p.gaveUp("a"))
    #expect(p.showPermissionBanner)
}

@Test func silenceAfterPermissionConfirmedKeepsCapture() {
    var p = MixerPolicy()
    #expect(p.respond(to: .healthy, for: "b") == .keep)
    #expect(p.respond(to: .silent, for: "a") == .keep)
    #expect(!p.gaveUp("a"))
    #expect(!p.showPermissionBanner)
}

@Test func healthyClearsBanner() {
    var p = MixerPolicy()
    _ = p.respond(to: .silent, for: "a")
    _ = p.respond(to: .healthy, for: "b")
    #expect(!p.showPermissionBanner)
}
