import Foundation

public struct ZonesState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public private(set) var presets: [Preset]
    public private(set) var assignments: [String: UUID]
    /// Starred layouts, in the order they were starred.
    public private(set) var favourites: [UUID]
    /// Per display: layouts applied there, most recent first.
    public private(set) var recents: [String: [UUID]]

    public static let panelTileCount = 6
    public static let maxFavourites = 6

    private enum CodingKeys: String, CodingKey {
        case version, presets, assignments, favourites, recents
    }

    public init(version: Int = 1, presets: [Preset], assignments: [String: UUID] = [:],
                favourites: [UUID] = [], recents: [String: [UUID]] = [:]) {
        self.version = version
        self.presets = presets.isEmpty ? StarterPresets.all : presets
        self.assignments = assignments
        self.favourites = favourites
        self.recents = recents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let presets = try c.decode([Preset].self, forKey: .presets)
        self.init(
            version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            presets: presets,
            assignments: try c.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? [:],
            // Favourites and recents are non-essential: a malformed value must never make the
            // whole file (and every layout in it) count as corrupt, so decode them leniently.
            favourites: (try? c.decodeIfPresent(LenientUUIDList.self, forKey: .favourites))?.ids ?? [],
            recents: (try? c.decodeIfPresent([String: LenientUUIDList].self, forKey: .recents))?
                .mapValues(\.ids) ?? [:]
        )
    }

    public func isFavourite(_ id: UUID) -> Bool { favourites.contains(id) }

    @discardableResult
    public mutating func setFavourite(_ id: UUID, _ on: Bool) -> Bool {
        guard presets.contains(where: { $0.id == id }) else { return false }
        if on {
            if favourites.contains(id) { return true }
            guard favourites.count < Self.maxFavourites else { return false }
            favourites.append(id)
        } else {
            favourites.removeAll { $0 == id }
        }
        return true
    }

    public mutating func touchRecent(_ id: UUID, forDisplay display: String) {
        guard presets.contains(where: { $0.id == id }) else { return }
        var list = recents[display] ?? []
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        recents[display] = list
    }

    /// Makes `id` the display's active layout. If it's already one of the display's
    /// panel tiles, the tiles keep their order: the visible non-favourite tiles are
    /// written into the recent list as they stand, so neither the clicked tile nor the
    /// one that was only shown because it was active moves. Otherwise it goes to the
    /// front of the recent list.
    public mutating func apply(_ id: UUID, forDisplay display: String) {
        let shown = panelTiles(forDisplay: display).map(\.id)
        if shown.contains(id) {
            let favs = Set(favourites)
            let frozen = shown.filter { !favs.contains($0) }
            let rest = (recents[display] ?? []).filter { !frozen.contains($0) }
            recents[display] = frozen + rest
        } else {
            touchRecent(id, forDisplay: display)
        }
        setActive(id, forDisplay: display)
    }

    /// Favourites, then this display's recents, then library order; the active layout is always shown.
    public func panelTiles(forDisplay display: String) -> [Preset] {
        let byID = Dictionary(presets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var tiles: [Preset] = []
        let order = favourites + (recents[display] ?? []) + presets.map(\.id)
        for id in order {
            guard tiles.count < Self.panelTileCount, let p = byID[id], seen.insert(id).inserted else { continue }
            tiles.append(p)
        }
        let active = activePreset(forDisplay: display)
        if !seen.contains(active.id) {
            let favs = Set(favourites)
            let slot = tiles.lastIndex(where: { !favs.contains($0.id) }) ?? tiles.count - 1
            tiles[slot] = active
        }
        return tiles
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
        favourites.removeAll { $0 == id }
        for (display, list) in recents { recents[display] = list.filter { $0 != id } }
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
        let known = Set(s.presets.map(\.id))
        var seenFav = Set<UUID>()
        s.favourites = Array(favourites.filter { known.contains($0) && seenFav.insert($0).inserted }.prefix(Self.maxFavourites))
        s.recents = recents.mapValues { $0.filter { known.contains($0) } }
        return s
    }
}

/// Decodes a JSON array keeping only the elements that are valid UUIDs; anything else
/// (wrong element types, or a non-array value) yields an empty list instead of throwing.
private struct LenientUUIDList: Decodable {
    let ids: [UUID]

    private struct Element: Decodable {
        let id: UUID?
        init(from decoder: Decoder) throws {
            id = try? decoder.singleValueContainer().decode(UUID.self)
        }
    }

    init(from decoder: Decoder) throws {
        ids = ((try? [Element](from: decoder)) ?? []).compactMap(\.id)
    }
}
