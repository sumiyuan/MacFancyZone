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

    /// Set when an AX call returned `.apiDisabled` even though
    /// `AXIsProcessTrusted()` may report true (e.g. a stale grant).
    /// Cleared by the next successful AX call.
    private var axWriteDisabled = false

    /// True if the process isn't trusted for Accessibility, or the last
    /// permission-relevant AX call failed with `.apiDisabled`.
    var permissionNeeded: Bool {
        axWriteDisabled || !Accessibility.isTrusted()
    }

    /// Call when an AX call (read or write) returned `.apiDisabled`.
    func noteAXWriteDisabled() {
        axWriteDisabled = true
    }

    /// Call when an AX call succeeded, so a stale `.apiDisabled` mark is cleared.
    func noteAXWorking() {
        axWriteDisabled = false
    }

    private var dragMonitor: DragMonitor?
    private lazy var switcher: SwitcherController = {
        let switcher = SwitcherController { [weak self] in self?.noteAXWriteDisabled() }
        switcher.onPermissionRestored = { [weak self] in self?.noteAXWorking() }
        return switcher
    }()

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

        let monitor = DragMonitor(controller: self)
        monitor.start()
        dragMonitor = monitor

        switcher.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if !Accessibility.isTrusted() {
            // Defer until the run loop is running so the alert can come forward.
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionAlert()
            }
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Retries the hotkey if it couldn't start earlier (e.g. permission granted since).
        switcher.start()
        menuBuilder.populate(menu, state: .init(
            monitors: ScreenIdentity.monitors().map(\.info),
            zones: state,
            permissionNeeded: permissionNeeded,
            launchAtLogin: LaunchAtLogin.isEnabled ? .on : (LaunchAtLogin.needsApproval ? .mixed : .off),
            windowSwitcherEnabled: switcher.isEnabled,
            editingPresetID: editor?.mode == .editCurrent ? editor?.presetID : nil
        ))
    }

    // MARK: State

    /// Alerts here are deferred until the run loop is running (this runs from `start()`,
    /// before `app.run()`).
    private func loadState() {
        switch store.load() {
        case .loaded(let s):
            state = s
        case .firstLaunch(let s):
            state = s
            saveDeferringErrors(s)
        case .recoveredFromCorruptFile(let s, let moved):
            state = s
            saveDeferringErrors(s)
            DispatchQueue.main.async { [weak self] in
                self?.showInfo("Presets file was unreadable",
                               "zones.json could not be parsed. It was moved to \(moved.path) and the starter presets were restored.")
            }
        case .unreadable(let s, let reason):
            state = s
            canSave = false
            DispatchQueue.main.async { [weak self] in
                self?.showInfo("Couldn't load presets",
                               "\(reason)\n\nChanges won't be saved this session, so your existing zones.json is left untouched.")
            }
        }
    }

    private func saveDeferringErrors(_ s: ZonesState) {
        do {
            try store.save(s)
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self] in
                self?.showInfo("Couldn't save presets", message)
            }
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

    /// The open editor and what it was opened for.
    private struct EditorSession {
        let controller: EditorWindowController
        let display: String       // ScreenIdentity.uuid of the edited screen
        let screenFrame: CGRect   // that screen's frame when the editor opened
        let mode: EditorMode
        let presetID: UUID
    }

    /// The open editor, if any. Only one at a time; released on save or cancel.
    private var editor: EditorSession?

    func openEditor(for screen: NSScreen, mode: EditorMode) {
        let display = ScreenIdentity.uuid(for: screen)
        if let editor {
            if editor.display == display, editor.mode == mode {
                editor.controller.show()
                return
            }
            // A different request: the open editor only holds a draft, so drop it.
            editor.controller.cancel()
            self.editor = nil
        }
        let draft: Preset
        switch mode {
        case .new: draft = Preset(id: UUID(), name: state.nextLayoutName(), layout: .zone)
        case .editCurrent: draft = activePreset(for: screen)
        }
        let controller = EditorWindowController(screen: screen, draft: draft) { [weak self] preset in
            self?.saveFromEditor(preset, mode: mode, display: display)
        }
        controller.onClose = { [weak self, weak controller] in
            // Deferred by the editor, so a newer editor may already be open; only clear our own.
            guard let self, let controller, self.editor?.controller === controller else { return }
            self.editor = nil
        }
        editor = EditorSession(controller: controller, display: display, screenFrame: screen.frame,
                               mode: mode, presetID: draft.id)
        controller.show()
    }

    private func saveFromEditor(_ edited: Preset, mode: EditorMode, display: String) {
        var preset = edited
        var activate = mode == .new
        if mode == .editCurrent, !state.presets.contains(where: { $0.id == preset.id }) {
            // Deleted from the menu while being edited: don't silently bring it back.
            let alert = NSAlert()
            alert.messageText = "This layout was deleted while you were editing it. Save it as a new layout?"
            alert.addButton(withTitle: "Save as New")
            alert.addButton(withTitle: "Discard")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            preset.id = UUID()
            activate = true
        }
        mutate { state in
            state.upsert(preset)
            if activate { state.setActive(preset.id, forDisplay: display) }
        }
    }

    /// The preset being edited in place, which can't be renamed or deleted meanwhile.
    private func isBeingEdited(_ id: UUID) -> Bool {
        editor?.mode == .editCurrent && editor?.presetID == id
    }

    /// Cancels the editor if its screen went away or changed geometry.
    @objc private func screenParametersChanged() {
        guard let editor else { return }
        let screen = NSScreen.screens.first { ScreenIdentity.uuid(for: $0) == editor.display }
        if screen?.frame != editor.screenFrame {
            editor.controller.cancel()
            self.editor = nil
        }
    }

    @objc func renamePreset(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let id = p.presetID,
              !isBeingEdited(id),
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
              state.presets.count > 1, !isBeingEdited(id),
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
            if LaunchAtLogin.needsApproval {
                // Registered but not yet approved: clicking turns it off rather than
                // registering again.
                try LaunchAtLogin.setEnabled(false)
                return
            }
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
            if LaunchAtLogin.needsApproval {
                // The user has to allow it in System Settings > Login Items.
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            showError("Couldn't change Launch at Login", error)
        }
    }

    @objc func toggleWindowSwitcher() {
        switcher.isEnabled.toggle()
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
