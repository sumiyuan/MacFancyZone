import Testing
import Foundation
@testable import ZonesCore

private func customPresets(_ n: Int) -> [Preset] {
    (0..<n).map { Preset(id: UUID(), name: "P\($0)", layout: StarterPresets.all[0].layout) }
}

@Suite struct ZonesStatePanelTests {
    @Test func decodesOldFormatWithoutNewFields() throws {
        let s = StarterPresets.all
        let presetsJSON = String(data: try JSONEncoder().encode(s), encoding: .utf8)!
        let json = "{\"version\":1,\"presets\":\(presetsJSON),\"assignments\":{\"D1\":\"\(s[1].id.uuidString)\"}}"
        let state = try JSONDecoder().decode(ZonesState.self, from: Data(json.utf8))
        #expect(state.presets == s)
        #expect(state.assignments == ["D1": s[1].id])
        #expect(state.favourites == [])
        #expect(state.recents == [:])
    }

    @Test func roundTripsFavouritesAndRecents() throws {
        let s = StarterPresets.all
        var state = ZonesState(presets: s)
        state.setFavourite(s[2].id, true)
        state.touchRecent(s[1].id, forDisplay: "D1")
        let back = try JSONDecoder().decode(ZonesState.self, from: JSONEncoder().encode(state))
        #expect(back == state)
        #expect(back.favourites == [s[2].id])
        #expect(back.recents == ["D1": [s[1].id]])
    }

    @Test func touchRecentMovesToFrontPerDisplay() {
        let s = StarterPresets.all
        var state = ZonesState(presets: s)
        state.touchRecent(s[0].id, forDisplay: "D1")
        state.touchRecent(s[1].id, forDisplay: "D1")
        state.touchRecent(s[0].id, forDisplay: "D1")
        #expect(state.recents["D1"] == [s[0].id, s[1].id])
        #expect(state.recents["D2"] == nil)
    }

    @Test func applySetsActive() {
        let s = StarterPresets.all
        var state = ZonesState(presets: s)
        state.apply(s[2].id, forDisplay: "D1")
        #expect(state.activePreset(forDisplay: "D1").id == s[2].id)
    }

    @Test func applyKeepsClickedTileInPlace() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        for i in [6, 4, 3, 2, 1] { state.touchRecent(p[i].id, forDisplay: "D1") }
        state.setActive(p[1].id, forDisplay: "D1")
        let before = state.panelTiles(forDisplay: "D1").map(\.id)
        #expect(before == [p[1], p[2], p[3], p[4], p[6], p[0]].map(\.id))
        state.apply(p[4].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == before)
        #expect(state.activePreset(forDisplay: "D1").id == p[4].id)
    }

    @Test func applyKeepsPreviouslyActiveTileVisible() {
        // p7 is only on the grid because it's active; switching away must not drop it.
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        for i in [5, 4, 3, 2, 1] { state.touchRecent(p[i].id, forDisplay: "D1") }
        state.setActive(p[7].id, forDisplay: "D1")
        let before = state.panelTiles(forDisplay: "D1").map(\.id)
        #expect(before == [p[1], p[2], p[3], p[4], p[5], p[7]].map(\.id))
        state.apply(p[2].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == before)
    }

    @Test func applyKeepsFavouritesAndOtherDisplaysUntouched() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        state.setFavourite(p[5].id, true)
        state.touchRecent(p[6].id, forDisplay: "D2")
        let d2Before = state.recents["D2"]
        let before = state.panelTiles(forDisplay: "D1").map(\.id)
        state.apply(p[1].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == before)
        #expect(state.favourites == [p[5].id])
        #expect(state.recents["D2"] == d2Before)
    }

    @Test func applyOffGridPresetMovesToFront() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        state.apply(p[7].id, forDisplay: "D1")   // p7 isn't among the six library-filled tiles
        #expect(state.recents["D1"]?.first == p[7].id)
        #expect(state.panelTiles(forDisplay: "D1").first?.id == p[7].id)
    }

    @Test func favouriteCapIsSix() {
        let p = customPresets(7)
        var state = ZonesState(presets: p)
        for i in 0..<6 { let ok = state.setFavourite(p[i].id, true); #expect(ok) }
        let seventh = state.setFavourite(p[6].id, true)
        #expect(!seventh)
        #expect(state.favourites.count == 6)
        #expect(state.isFavourite(p[0].id))
        #expect(!state.isFavourite(p[6].id))
        let off = state.setFavourite(p[0].id, false)
        #expect(off)
        #expect(!state.isFavourite(p[0].id))
    }

    @Test func favouriteUnknownIdRejected() {
        var state = ZonesState.initial()
        let ok = state.setFavourite(UUID(), true)
        #expect(!ok)
        #expect(state.favourites.isEmpty)
    }

    @Test func panelTilesFavouritesThenRecentsThenLibrary() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        state.setFavourite(p[5].id, true)
        state.touchRecent(p[6].id, forDisplay: "D1")
        state.touchRecent(p[2].id, forDisplay: "D1")
        state.setActive(p[2].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == [p[5], p[2], p[6], p[0], p[1], p[3]].map(\.id))
    }

    @Test func activeTakesLastNonFavouriteTile() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        state.setFavourite(p[5].id, true)
        for i in [6, 4, 3, 2, 1] { state.touchRecent(p[i].id, forDisplay: "D1") }
        state.setActive(p[7].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == [p[5], p[1], p[2], p[3], p[4], p[7]].map(\.id))
    }

    @Test func activeReplacesSixthWhenAllFavourites() {
        let p = customPresets(8)
        var state = ZonesState(presets: p)
        for i in 0..<6 { state.setFavourite(p[i].id, true) }
        state.setActive(p[7].id, forDisplay: "D1")
        #expect(state.panelTiles(forDisplay: "D1").map(\.id) == [p[0], p[1], p[2], p[3], p[4], p[7]].map(\.id))
    }

    @Test func fewerThanSixPresetsShowsEachOnce() {
        let state = ZonesState.initial()
        let ids = state.panelTiles(forDisplay: "D1").map(\.id)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3)
    }

    @Test func panelTilesSkipUnknownIDs() {
        let p = customPresets(8)
        let ghost = UUID()
        let state = ZonesState(presets: p, favourites: [ghost], recents: ["D1": [ghost, p[3].id]])
        let ids = state.panelTiles(forDisplay: "D1").map(\.id)
        #expect(!ids.contains(ghost))
        #expect(ids.count == 6)
        #expect(ids.first == p[3].id)
    }

    @Test func deleteRemovesFromFavouritesAndRecents() {
        let s = StarterPresets.all
        var state = ZonesState(presets: s)
        state.setFavourite(s[1].id, true)
        state.touchRecent(s[1].id, forDisplay: "D1")
        state.touchRecent(s[1].id, forDisplay: "D2")
        state.touchRecent(s[0].id, forDisplay: "D2")
        let deleted = state.delete(s[1].id)
        #expect(deleted)
        #expect(state.favourites.isEmpty)
        #expect(state.recents["D1"] == [])
        #expect(state.recents["D2"] == [s[0].id])
    }

    @Test func sanitizedDropsUnknownAndCapsFavourites() {
        let p = customPresets(8)
        let ghost = UUID()
        let favs = [ghost] + p.map(\.id)
        let state = ZonesState(presets: p, favourites: favs, recents: ["D1": [ghost, p[0].id]])
        let clean = state.sanitized()
        #expect(clean.favourites == Array(p.prefix(6)).map(\.id))
        #expect(clean.recents["D1"] == [p[0].id])
    }
}
