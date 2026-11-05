import Foundation

/// One app's mixer setting: a volume from 0% to 150%, and whether it's muted.
public struct AppAudioSetting: Codable, Equatable, Sendable {
    public static let range: ClosedRange<Double> = 0...1.5
    public static let neutral = AppAudioSetting(volume: 1.0, muted: false)

    public var volume: Double {
        didSet { volume = Self.clamp(volume) }
    }
    public var muted: Bool

    public init(volume: Double, muted: Bool) {
        self.volume = Self.clamp(volume)
        self.muted = muted
    }

    private enum CodingKeys: String, CodingKey { case volume, muted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(volume: try c.decode(Double.self, forKey: .volume),
                  muted: try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false)
    }

    /// The multiplier applied to the app's samples.
    public var gain: Float { muted ? 0 : Float(volume) }

    /// An app at 100% and not muted is left alone: never captured.
    public var needsCapture: Bool { !(volume == 1.0 && !muted) }

    private static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 1.0 }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}
