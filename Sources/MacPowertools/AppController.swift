import AppKit
import ServiceManagement
import ZonesCore

/// Owns the status item and its menu, and drives the permission flow.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let store = PresetStore(directory: PresetStore.defaultDirectory())
    private(set) var state = ZonesState.initial()
    /// False after an `.unreadable` load: changes stay in memory, the user's file is never overwritten.
    private var canSave = true
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
        loadState()
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
            monitors: ScreenIdentity.monitors().map(\.info),
            zones: state,
            permissionNeeded: permissionNeeded,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled
        ))
    }

    // MARK: State

    private func loadState() {
        switch store.load() {
        case .loaded(let s):
            state = s
        case .firstLaunch(let s):
            state = s
            do { try store.save(s) } catch { showError("Couldn't save presets", error) }
        case .recoveredFromCorruptFile(let s, let moved):
            state = s
            do { try store.save(s) } catch { showError("Couldn't save presets", error) }
            showInfo("Presets file was unreadable",
                     "zones.json could not be parsed. It was moved to \(moved.path) and the starter presets were restored.")
        case .unreadable(let s, let reason):
            state = s
            canSave = false
            showInfo("Couldn't load presets",
                     "\(reason)\n\nChanges won't be saved this session, so your existing zones.json is left untouched.")
        }
    }

    func mutate(_ change: (inout ZonesState) -> Void) {
        change(&state)
        guard canSave else { return }
        do { try store.save(state) } catch { showError("Couldn't save presets", error) }
    }

    func activePreset(for screen: NSScreen) -> Preset {
        state.activePreset(forDisplay: ScreenIdentity.uuid(for: screen))
    }

    private func screen(for monitorID: String) -> NSScreen? {
        ScreenIdentity.monitors().first { $0.info.id == monitorID }?.screen
    }

    // MARK: Preset actions

    @objc func selectPreset(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let preset = p.presetID else { return }
        mutate { $0.setActive(preset, forDisplay: p.monitorID) }
    }

    @objc func newLayout(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let screen = screen(for: p.monitorID) else { return }
        openEditor(for: screen, mode: .new)
    }

    @objc func editCurrentLayout(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let screen = screen(for: p.monitorID) else { return }
        openEditor(for: screen, mode: .editCurrent)
    }

    enum EditorMode { case new, editCurrent }

    // Task 10: replace with the real editor window.
    func openEditor(for screen: NSScreen, mode: EditorMode) {
        NSSound.beep()
    }

    @objc func renamePreset(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let id = p.presetID,
              let preset = state.presets.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Layout"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = preset.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        mutate { $0.rename(id, to: name) }
    }

    @objc func deletePreset(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let id = p.presetID,
              state.presets.count > 1,
              let preset = state.presets.first(where: { $0.id == id }),
              let fallback = state.presets.first(where: { $0.id != id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(preset.name)”?"
        alert.informativeText = "Monitors using it switch to “\(fallback.name)”."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { $0.delete(id) }
    }

    @objc func restoreStarterPresets() {
        mutate { $0.restoreStarters() }
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

    private func showInfo(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
