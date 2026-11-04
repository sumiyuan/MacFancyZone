import AppKit
import ServiceManagement

/// Owns the status item and its menu, and drives the permission flow.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private lazy var menuBuilder = MenuBuilder(target: self)

    /// Set when an AX write returned `.apiDisabled` even though
    /// `AXIsProcessTrusted()` reported true (e.g. a stale grant).
    private var axWriteDisabled = false

    /// True if the process isn't trusted for Accessibility, or an AX write
    /// failed with `.apiDisabled`. Set it to `true` after such a failure;
    /// setting it to `false` clears the write failure (it stays `true` while
    /// the process is still untrusted).
    var permissionNeeded: Bool {
        get { axWriteDisabled || !Accessibility.isTrusted() }
        set { axWriteDisabled = newValue }
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "MacPowertools")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        if !Accessibility.isTrusted() {
            // Defer until the run loop is running so the alert can come forward.
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionAlert()
            }
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuBuilder.populate(menu, state: .init(
            permissionNeeded: permissionNeeded,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled
        ))
    }

    // MARK: Actions

    @objc func openAccessibilitySettings() {
        Accessibility.openSettingsPane()
    }

    @objc func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
            if LaunchAtLogin.needsApproval {
                // The user has to allow it in System Settings > Login Items.
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            showError("Couldn't change Launch at Login", error)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Alerts

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
            MacPowertools snaps windows into zones by moving and resizing other apps' windows. \
            macOS only allows this for apps granted Accessibility access.

            Open System Settings, then turn on MacPowertools under Privacy & Security > Accessibility.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Accessibility.openSettingsPane()
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
