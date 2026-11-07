import Foundation

/// One Core Audio process object, as seen by the mixer.
public struct AudioProcess: Equatable, Sendable {
    public let objectID: UInt32
    public let pid: Int32
    public let isPlaying: Bool

    public init(objectID: UInt32, pid: Int32, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.isPlaying = isPlaying
    }
}

/// The regular app a sound-making process belongs to.
public struct OwningApp: Hashable, Sendable {
    public let bundleID: String
    public let name: String
    public let pid: Int32

    public init(bundleID: String, name: String, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// Walks up the parent chain from `pid` until `app` recognises a process. Gives up at
/// launchd (pid 1), a missing parent, or after 32 steps.
public func resolveOwner(pid: Int32, parent: (Int32) -> Int32?, app: (Int32) -> OwningApp?) -> OwningApp? {
    var current = pid
    for _ in 0..<32 {
        guard current > 1 else { return nil }
        if let owner = app(current) { return owner }
        guard let next = parent(current) else { return nil }
        current = next
    }
    return nil
}

/// The apps making sound now, plus those that went quiet less than `linger` seconds ago.
public struct SoundSources: Sendable {
    public static let linger: TimeInterval = 5

    private struct Entry: Sendable {
        var owner: OwningApp
        var lastPlayed: TimeInterval?
        var objects: [UInt32] = []
        var playing = false
    }

    private var entries: [String: Entry] = [:]
    private var now: TimeInterval = 0

    public init() {}

    public mutating func update(processes: [AudioProcess], owner: (Int32) -> OwningApp?, now: TimeInterval) {
        self.now = now
        for key in entries.keys {
            entries[key]?.objects = []
            entries[key]?.playing = false
        }
        for process in processes {
            guard let app = owner(process.pid) else { continue }
            var entry = entries[app.bundleID] ?? Entry(owner: app)
            entry.owner = app
            entry.objects.append(process.objectID)
            if process.isPlaying {
                entry.playing = true
                entry.lastPlayed = now
            }
            entries[app.bundleID] = entry
        }
        entries = entries.filter { _, e in
            !e.objects.isEmpty || e.lastPlayed.map { now - $0 <= Self.linger } == true
        }
    }

    public var rows: [OwningApp] {
        entries.values
            .filter { e in e.lastPlayed.map { now - $0 <= Self.linger } ?? false }
            .map(\.owner)
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
            }
    }

    /// All of the app's process objects in the latest update, playing or not.
    public func processObjects(for bundleID: String) -> [UInt32] {
        entries[bundleID]?.objects ?? []
    }

    /// Whether any of the app's processes was playing in the latest update.
    public func isPlaying(_ bundleID: String) -> Bool {
        entries[bundleID]?.playing ?? false
    }
}
