import Testing
import Foundation
@testable import ZonesCore

@Suite struct PresetMenuModelTests {
    @Test func singleMonitorSectionHasNoTitle() {
        let sections = presetMenuSections(state: .initial(), monitors: [MonitorInfo(id: "A", name: "Built-in")])
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].items.count == 3)
    }

    @Test func multiMonitorSectionsAreTitledAndChecked() {
        var s = ZonesState.initial()
        s.setActive(s.presets[1].id, forDisplay: "B")
        let sections = presetMenuSections(state: s, monitors: [MonitorInfo(id: "A", name: "Left"), MonitorInfo(id: "B", name: "Right")])
        #expect(sections.map(\.title) == ["Left", "Right"])
        for sec in sections { #expect(sec.items.filter(\.isActive).count == 1) }
        #expect(sections[0].items.first { $0.isActive }?.name == "2 Columns")
        #expect(sections[1].items.first { $0.isActive }?.name == "3 Columns")
    }
}
