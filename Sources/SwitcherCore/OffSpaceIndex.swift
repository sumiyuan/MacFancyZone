import Foundation

/// The 20-byte token accepted by the private `_AXUIElementCreateWithRemoteToken`:
/// pid (Int32), 0 (Int32), "coco" (0x636f636f), element ID (UInt64), all little-endian.
public enum RemoteToken {
    public static func data(pid: Int32, elementID: UInt64) -> Data {
        var data = Data(capacity: 20)
        withUnsafeBytes(of: pid.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(0).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(0x636f636f).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: elementID.littleEndian) { data.append(contentsOf: $0) }
        return data
    }
}

/// Remembers, per app, every window found by searching (on any desktop) and which system
/// window IDs have been searched for, so the expensive search runs only for new windows.
/// A found window stays known while it's visible normally, so it reappears when you leave it.
public struct OffSpaceIndex<Element> {
    private struct Entry {
        var looked: Set<UInt32> = []
        var elements: [UInt32: Element] = [:]
    }

    private var entries: [Int32: Entry] = [:]

    public init() {}

    /// System window IDs that are not visible normally, not known, and not searched for yet.
    public func missing(pid: Int32, systemWindowIDs: Set<UInt32>, visibleIDs: Set<UInt32>) -> Set<UInt32> {
        let entry = entries[pid]
        return systemWindowIDs
            .subtracting(visibleIDs)
            .subtracting(entry?.looked ?? [])
            .subtracting(entry?.elements.keys ?? [:].keys)
    }

    /// Records a search: every ID in `looked` was searched for; `found` are real windows.
    public mutating func recordScan(pid: Int32, looked: Set<UInt32>, found: [UInt32: Element]) {
        var entry = entries[pid] ?? Entry()
        entry.looked.formUnion(looked)
        entry.elements.merge(found) { _, new in new }
        entries[pid] = entry
    }

    /// Remembers a window seen normally, so it's known if it later moves to another desktop.
    public mutating func remember(pid: Int32, id: UInt32, element: Element) {
        entries[pid, default: Entry()].elements[id] = element
    }

    /// Known windows that aren't visible normally right now.
    public func offDesktop(pid: Int32, visibleIDs: Set<UInt32>) -> [UInt32: Element] {
        (entries[pid]?.elements ?? [:]).filter { !visibleIDs.contains($0.key) }
    }

    /// Forgets windows the system no longer lists (closed).
    public mutating func prune(pid: Int32, systemWindowIDs: Set<UInt32>) {
        guard var entry = entries[pid] else { return }
        entry.looked.formIntersection(systemWindowIDs)
        entry.elements = entry.elements.filter { systemWindowIDs.contains($0.key) }
        entries[pid] = entry
    }

    /// Forgets apps that have quit.
    public mutating func retain(pids: Set<Int32>) {
        entries = entries.filter { pids.contains($0.key) }
    }
}

