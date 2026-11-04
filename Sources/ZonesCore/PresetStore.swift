import Foundation

public enum LoadResult: Equatable, Sendable {
    case loaded(ZonesState)
    case firstLaunch(ZonesState)
    case recoveredFromCorruptFile(ZonesState, movedTo: URL)

    public var state: ZonesState {
        switch self {
        case .loaded(let s), .firstLaunch(let s), .recoveredFromCorruptFile(let s, _): return s
        }
    }
}

public struct PresetStore: Sendable {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("zones.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacPowertools", isDirectory: true)
    }

    public func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .firstLaunch(.initial()) }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(ZonesState.self, from: data)
            return .loaded(state.sanitized())
        } catch {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            var target = directory.appendingPathComponent("zones.corrupt-\(stamp).json")
            var n = 1
            while fm.fileExists(atPath: target.path) {
                target = directory.appendingPathComponent("zones.corrupt-\(stamp)-\(n).json")
                n += 1
            }
            do {
                try fm.moveItem(at: fileURL, to: target)
            } catch {
                // Could not move aside; still recover with defaults.
            }
            return .recoveredFromCorruptFile(.initial(), movedTo: target)
        }
    }

    public func save(_ state: ZonesState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
