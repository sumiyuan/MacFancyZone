import Foundation

/// Reads and writes `mixer.json`. Loading never fails: anything unreadable gives empty settings.
public struct MixerStore: Sendable {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("mixer.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() -> MixerSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(MixerSettings.self, from: data) else {
            return MixerSettings()
        }
        return settings
    }

    public func save(_ settings: MixerSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
