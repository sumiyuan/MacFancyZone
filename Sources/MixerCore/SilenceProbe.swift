import Foundation

/// Decides whether a fresh capture is delivering sound. Without the System Audio Recording
/// permission a tap can deliver only silence while still muting the app, so a capture that
/// hears nothing for `timeout` seconds of playing time is reported `.silent`.
public struct SilenceProbe: Sendable {
    public static let timeout: TimeInterval = 3

    public enum Verdict: Equatable, Sendable { case pending, healthy, silent }

    private var last: TimeInterval
    private var playingTime: TimeInterval = 0
    private var heard = false

    public init(startedAt: TimeInterval) {
        last = startedAt
    }

    /// Time since the previous call only counts if the source is playing now.
    public mutating func observe(heardSound: Bool, sourcePlaying: Bool, now: TimeInterval) -> Verdict {
        if heardSound { heard = true }
        if heard { return .healthy }
        if sourcePlaying { playingTime += max(0, now - last) }
        last = now
        return playingTime > Self.timeout ? .silent : .pending
    }
}
