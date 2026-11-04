import Foundation

public struct MonitorInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct PresetItem: Equatable, Sendable {
    public let presetID: UUID
    public let name: String
    public let isActive: Bool
    public init(presetID: UUID, name: String, isActive: Bool) {
        self.presetID = presetID; self.name = name; self.isActive = isActive
    }
}

public struct MonitorSection: Equatable, Sendable {
    public let monitorID: String
    public let title: String?
    public let items: [PresetItem]
    public init(monitorID: String, title: String?, items: [PresetItem]) {
        self.monitorID = monitorID; self.title = title; self.items = items
    }
}

public func presetMenuSections(state: ZonesState, monitors: [MonitorInfo]) -> [MonitorSection] {
    monitors.map { monitor in
        let activeID = state.activePreset(forDisplay: monitor.id).id
        return MonitorSection(
            monitorID: monitor.id,
            title: monitors.count == 1 ? nil : monitor.name,
            items: state.presets.map { PresetItem(presetID: $0.id, name: $0.name, isActive: $0.id == activeID) })
    }
}
