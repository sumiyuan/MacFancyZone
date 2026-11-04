import Foundation

public struct ZonesState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public private(set) var presets: [Preset]
    public private(set) var assignments: [String: UUID]

    public init(version: Int = 1, presets: [Preset], assignments: [String: UUID] = [:]) {
        self.version = version
        self.presets = presets.isEmpty ? StarterPresets.all : presets
        self.assignments = assignments
    }

    public static func initial() -> ZonesState {
        ZonesState(presets: StarterPresets.all)
    }

    public func activePreset(forDisplay display: String) -> Preset {
        if let id = assignments[display], let p = presets.first(where: { $0.id == id }) { return p }
        return presets[0]
    }

    public mutating func setActive(_ presetID: UUID, forDisplay display: String) {
        assignments[display] = presetID
    }

    public mutating func upsert(_ preset: Preset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
    }

    @discardableResult
    public mutating func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return false }
        presets[i].name = trimmed
        return true
    }

    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        guard presets.count > 1, let i = presets.firstIndex(where: { $0.id == id }) else { return false }
        presets.remove(at: i)
        let fallback = presets[0].id
        for (display, assigned) in assignments where assigned == id {
            assignments[display] = fallback
        }
        return true
    }

    public mutating func restoreStarters() {
        for starter in StarterPresets.all where !presets.contains(where: { $0.id == starter.id }) {
            presets.append(starter)
        }
    }

    public func nextLayoutName() -> String {
        let used = Set(presets.map(\.name))
        var n = 1
        while used.contains("Layout \(n)") { n += 1 }
        return "Layout \(n)"
    }

    public func sanitized() -> ZonesState {
        var s = self
        s.presets = presets.map { $0.sanitized() }
        if s.presets.isEmpty { s.presets = StarterPresets.all }
        return s
    }
}
