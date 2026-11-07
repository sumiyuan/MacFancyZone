import Foundation

/// Every app's mixer setting, keyed by the owning app's bundle ID. Apps at the neutral
/// setting aren't stored.
public struct MixerSettings: Codable, Equatable, Sendable {
    public private(set) var apps: [String: AppAudioSetting]

    public init(apps: [String: AppAudioSetting] = [:]) {
        self.apps = apps.filter { $0.value != .neutral }
    }

    private enum CodingKeys: String, CodingKey { case apps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lenient = (try? c.decodeIfPresent([String: LenientSetting].self, forKey: .apps)) ?? nil
        self.init(apps: (lenient ?? [:]).compactMapValues(\.setting))
    }

    public func setting(for bundleID: String) -> AppAudioSetting {
        apps[bundleID] ?? .neutral
    }

    /// Sets the volume (clamped to 0...1.5). Moving the slider also unmutes.
    public mutating func setVolume(_ v: Double, for bundleID: String) {
        store(AppAudioSetting(volume: v, muted: false), for: bundleID)
    }

    /// Mutes or unmutes, keeping the volume so unmuting restores it.
    public mutating func setMuted(_ m: Bool, for bundleID: String) {
        var s = setting(for: bundleID)
        s.muted = m
        store(s, for: bundleID)
    }

    private mutating func store(_ s: AppAudioSetting, for bundleID: String) {
        apps[bundleID] = s == .neutral ? nil : s
    }
}

/// Decodes one entry, yielding nil instead of throwing when it's malformed.
private struct LenientSetting: Decodable {
    let setting: AppAudioSetting?
    init(from decoder: Decoder) throws {
        setting = try? AppAudioSetting(from: decoder)
    }
}
