import Foundation

public enum LoadResult: Equatable, Sendable {
    case loaded(ZonesState)
    case firstLaunch(ZonesState)
    case recoveredFromCorruptFile(ZonesState, movedTo: URL)
    /// zones.json exists but could not be read, or could not be moved aside after failing to decode.
    /// The file is left untouched. Callers must not call save() for the rest of the session,
    /// or the user's data would be overwritten.
    case unreadable(ZonesState, reason: String)

    public var state: ZonesState {
        switch self {
        case .loaded(let s), .firstLaunch(let s), .recoveredFromCorruptFile(let s, _), .unreadable(let s, _): return s
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
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .unreadable(.initial(), reason: "Could not read zones.json: \(error.localizedDescription)")
        }
        do {
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
                return .unreadable(.initial(), reason: "Could not move corrupt zones.json aside: \(error.localizedDescription)")
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
