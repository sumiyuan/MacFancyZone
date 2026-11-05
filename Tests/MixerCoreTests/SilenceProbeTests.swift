import Testing
@testable import MixerCore

@Test func probeHealthyOnceSoundHeard() {
    var p = SilenceProbe(startedAt: 0)
    #expect(p.observe(heardSound: true, sourcePlaying: true, now: 0.5) == .healthy)
    #expect(p.observe(heardSound: false, sourcePlaying: true, now: 10) == .healthy)
}

@Test func probeReportsSilentAfterThreeSeconds() {
    var p = SilenceProbe(startedAt: 0)
    #expect(p.observe(heardSound: false, sourcePlaying: true, now: 2.9) == .pending)
    #expect(p.observe(heardSound: false, sourcePlaying: true, now: 3.1) == .silent)
}

@Test func probeClockPausesWhileSourceQuiet() {
    var p = SilenceProbe(startedAt: 0)
    _ = p.observe(heardSound: false, sourcePlaying: true, now: 2)
    _ = p.observe(heardSound: false, sourcePlaying: false, now: 10)
    #expect(p.observe(heardSound: false, sourcePlaying: true, now: 10.5) == .pending)
}
