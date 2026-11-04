import Testing
import Foundation
@testable import ZonesCore

@Suite struct ZonesStateTests {
    @Test func initialStateHasThreeStartersInOrder() {
        #expect(ZonesState.initial().presets.map(\.name) == ["2 Columns", "3 Columns", "Wide Center"])
    }

    @Test func wideCenterWidthsAre25_50_25() {
        let widths = StarterPresets.all[2].layout.zones().map(\.unitRect.width)
        #expect(widths.count == 3)
        for (w, e) in zip(widths, [0.25, 0.5, 0.25]) { #expect(abs(w - e) < 1e-9) }
    }

    @Test func unseenDisplayGetsFirstPreset() {
        let s = ZonesState.initial()
        #expect(s.activePreset(forDisplay: "A") == s.presets[0])
    }

    @Test func danglingAssignmentFallsBackToFirstPreset() {
        var s = ZonesState.initial()
        s.setActive(UUID(), forDisplay: "A")
        #expect(s.activePreset(forDisplay: "A") == s.presets[0])
    }

    @Test func activePresetIsPerDisplay() {
        var s = ZonesState.initial()
        s.setActive(s.presets[1].id, forDisplay: "A")
        s.setActive(s.presets[2].id, forDisplay: "B")
        #expect(s.activePreset(forDisplay: "A").name == "3 Columns")
        #expect(s.activePreset(forDisplay: "B").name == "Wide Center")
        #expect(s.activePreset(forDisplay: "C").name == "2 Columns")
    }

    @Test func deleteReassignsMonitorsToFirstRemaining() {
        var s = ZonesState.initial()
        let first = s.presets[0].id
        s.setActive(first, forDisplay: "A")
        s.setActive(first, forDisplay: "B")
        let ok = s.delete(first)
        #expect(ok)
        #expect(s.activePreset(forDisplay: "A").name == "3 Columns")
        #expect(s.activePreset(forDisplay: "B").name == "3 Columns")
        #expect(s.assignments["A"] == s.presets[0].id)
        #expect(s.assignments["B"] == s.presets[0].id)
    }

    @Test func cannotDeleteLastPreset() {
        var s = ZonesState.initial()
        let a = s.delete(s.presets[0].id)
        let b = s.delete(s.presets[0].id)
        let c = s.delete(s.presets[0].id)
        #expect(a && b && !c)
        #expect(s.presets.count == 1)
    }

    @Test func renameRejectsBlankName() {
        var s = ZonesState.initial()
        let id = s.presets[0].id
        let blank = s.rename(id, to: "   ")
        #expect(!blank)
        #expect(s.presets[0].name == "2 Columns")
        let ok = s.rename(id, to: " Mine ")
        #expect(ok)
        #expect(s.presets[0].name == "Mine")
    }

    @Test func restoreStartersAddsOnlyMissing() {
        var s = ZonesState.initial()
        _ = s.delete(s.presets[1].id)
        var edited = s.presets[0]
        edited.name = "Edited"
        s.upsert(edited)
        s.restoreStarters()
        #expect(s.presets.count == 3)
        #expect(s.presets.contains { $0.name == "Edited" })
        #expect(s.presets.contains { $0.name == "3 Columns" })
    }

    @Test func nextLayoutNameSkipsUsed() {
        var s = ZonesState.initial()
        #expect(s.nextLayoutName() == "Layout 1")
        s.upsert(Preset(id: UUID(), name: "Layout 1", layout: .zone))
        #expect(s.nextLayoutName() == "Layout 2")
    }

    @Test func sanitizedClampsSpacing() {
        var s = ZonesState.initial()
        s.upsert(Preset(id: UUID(), name: "Hi", layout: .zone, spacing: 500))
        s.upsert(Preset(id: UUID(), name: "Lo", layout: .zone, spacing: -3))
        let c = s.sanitized().presets
        #expect(c.first { $0.name == "Hi" }?.spacing == 64)
        #expect(c.first { $0.name == "Lo" }?.spacing == 0)
    }

    @Test func codableRoundTrip() throws {
        var s = ZonesState.initial()
        s.setActive(s.presets[1].id, forDisplay: "A")
        let back = try JSONDecoder().decode(ZonesState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
