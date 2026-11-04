import AppKit

/// Builds the status item menu. `AppController` calls `populate` from
/// `menuNeedsUpdate`, so the menu always reflects current state.
@MainActor
struct MenuBuilder {
    /// Everything the menu needs to render.
    struct State {
        var permissionNeeded: Bool
        var launchAtLoginEnabled: Bool
    }

    let target: AppController

    func populate(_ menu: NSMenu, state: State) {
        menu.removeAllItems()

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
