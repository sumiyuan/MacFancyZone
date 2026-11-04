import AppKit
import ZonesCore

/// Per-item payload carried in `representedObject`.
final class MenuPayload: NSObject {
    let monitorID: String
    let presetID: UUID?
    init(monitorID: String, presetID: UUID? = nil) {
        self.monitorID = monitorID
        self.presetID = presetID
    }
}

/// Builds the status item menu. `AppController` calls `populate` from
/// `menuNeedsUpdate`, so the menu always reflects current state.
@MainActor
struct MenuBuilder {
    /// Everything the menu needs to render.
    struct State {
        var monitors: [MonitorInfo]
        var zones: ZonesState
        var permissionNeeded: Bool
        var launchAtLoginEnabled: Bool
    }

    let target: AppController

    func populate(_ menu: NSMenu, state: State) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let sections = presetMenuSections(state: state.zones, monitors: state.monitors)
        for section in sections {
            if let title = section.title {
                let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
            for preset in section.items {
                let it = item(preset.name, #selector(AppController.selectPreset(_:)))
                it.state = preset.isActive ? .on : .off
                it.representedObject = MenuPayload(monitorID: section.monitorID, presetID: preset.presetID)
                menu.addItem(it)
            }
            menu.addItem(.separator())
            let activeID = section.items.first(where: \.isActive)?.presetID
            let payload = MenuPayload(monitorID: section.monitorID, presetID: activeID)
            for (title, action) in [("New Layout…", #selector(AppController.newLayout(_:))),
                                    ("Edit Current Layout…", #selector(AppController.editCurrentLayout(_:))),
                                    ("Rename…", #selector(AppController.renamePreset(_:))),
                                    ("Delete", #selector(AppController.deletePreset(_:)))] {
                let it = item(title, action)
                it.representedObject = payload
                if title == "Delete" { it.isEnabled = state.zones.presets.count > 1 }
                menu.addItem(it)
            }
            menu.addItem(.separator())
        }
        menu.addItem(item("Restore Starter Presets", #selector(AppController.restoreStarterPresets)))
        menu.addItem(.separator())

        if state.permissionNeeded {
            menu.addItem(item("Accessibility permission needed…", #selector(AppController.openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let launch = item("Launch at Login", #selector(AppController.toggleLaunchAtLogin))
        launch.state = state.launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        menu.addItem(item("Quit MacPowertools", #selector(AppController.quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
