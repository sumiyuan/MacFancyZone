import Foundation

public struct RecencyList<Key: Hashable & Sendable>: Sendable {
    /// Most recent first, no duplicates.
    public private(set) var items: [Key] = []

    public init() {}

    public mutating func touch(_ key: Key) {
        if let i = items.firstIndex(of: key) { items.remove(at: i) }
        items.insert(key, at: 0)
    }

    public mutating func prune(keeping alive: Set<Key>) {
        items.removeAll { !alive.contains($0) }
    }

    public func rank(of key: Key) -> Int? {
        items.firstIndex(of: key)
    }
}

public struct WindowCandidate<Key: Hashable & Sendable>: Sendable {
    public let key: Key
    public let appPID: Int32

    public init(key: Key, appPID: Int32) {
        self.key = key
        self.appPID = appPID
    }
}

public enum RecencyOrdering {
    /// `candidates` arrive in enumeration order (apps in order, each app's windows in AX order).
    /// Tracked windows first by rank; then untracked grouped by app rank (unknown apps last);
    /// enumeration order preserved within a group.
    public static func order<Key>(_ candidates: [WindowCandidate<Key>],
                                  windows: RecencyList<Key>,
                                  apps: RecencyList<Int32>) -> [Key] {
        let keyed = candidates.enumerated().map { (index, c) -> (tier: Int, rank: Int, index: Int, key: Key) in
            if let r = windows.rank(of: c.key) { return (0, r, index, c.key) }
            return (1, apps.rank(of: c.appPID) ?? Int.max, index, c.key)
        }
        return keyed.sorted {
            ($0.tier, $0.rank, $0.index) < ($1.tier, $1.rank, $1.index)
        }.map(\.key)
    }
}
