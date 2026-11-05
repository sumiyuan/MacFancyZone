import AppKit
import Observation

/// One app's row in the Volume Mixer card.
struct MixerRow: Identifiable, Equatable {
    let id: String          // bundle ID
    let name: String
    let icon: NSImage?
    let volume: Double
    let muted: Bool
    /// Capture failed: the slider is disabled and a hint shows.
    let unavailable: Bool
}

/// State and actions for the Volume Mixer card. `MixerController` fills it in.
@MainActor @Observable
final class MixerModel {
    var rows: [MixerRow] = []
    var permissionNeeded = false

    var onSetVolume: (String, Double) -> Void = { _, _ in }
    var onToggleMute: (String) -> Void = { _ in }
    var onOpenAudioSettings: () -> Void = {}
}
