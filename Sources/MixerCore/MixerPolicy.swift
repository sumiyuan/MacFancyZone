import Foundation

/// The mixer's decisions about when to capture an app and what to do when a capture is
/// silent. Pure, so it can be tested without audio hardware.
public struct MixerPolicy: Sendable {
    public static let maxSetupFailures = 3

    public enum SilenceResponse: Equatable, Sendable { case keep, giveUp }

    /// True once any capture has delivered sound this session, so the permission is granted.
    public private(set) var permissionConfirmed = false
    /// True after a capture was abandoned for silence before the permission was confirmed.
    public private(set) var showPermissionBanner = false
    private var failures: [String: Int] = [:]
    private var silenced: Set<String> = []

    public init() {}

    /// An app is captured when its setting needs it, it has processes to tap, and it
    /// hasn't been given up on.
    public func shouldCapture(_ id: String, setting: AppAudioSetting, processCount: Int) -> Bool {
        setting.needsCapture && processCount > 0 && !gaveUp(id)
    }

    public func gaveUp(_ id: String) -> Bool {
        silenced.contains(id) || failures[id, default: 0] >= Self.maxSetupFailures
    }

    public mutating func setupFailed(_ id: String) { failures[id, default: 0] += 1 }
    public mutating func setupSucceeded(_ id: String) { failures[id] = nil }

    /// Gives every app another try (the panel was opened).
    public mutating func resetFailures() {
        failures.removeAll()
        silenced.removeAll()
    }

    /// Silence only means a missing permission until some capture has proved it granted;
    /// after that a silent capture is just a quiet app and is kept.
    public mutating func respond(to verdict: SilenceProbe.Verdict, for id: String) -> SilenceResponse {
        switch verdict {
        case .healthy:
            permissionConfirmed = true
            showPermissionBanner = false
            return .keep
        case .pending:
            return .keep
        case .silent:
            guard !permissionConfirmed else { return .keep }
            silenced.insert(id)
            showPermissionBanner = true
            return .giveUp
        }
    }
}
