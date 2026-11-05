import AppKit
import ServiceManagement
import SwiftUI
import ZonesCore

/// Owns the status item and its panel, and drives the permission flow.
@MainActor
final class AppController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let store = PresetStore(directory: PresetStore.defaultDirectory())
    private(set) var state = ZonesState.initial()
    /// False after an `.unreadable` load: changes stay in memory, the user's file is never overwritten.
    private var canSave = true

    private let panel = PanelModel()
    private let popover = NSPopover()
    /// Watches for Esc while the popover is shown; removed when it closes.
    private var escMonitor: Any?
    /// Set by New / Edit / All layouts before closing the popover, so the app stays active
    /// for the window they open.
    private var keepActiveOnClose = false
    /// When a click on the status button closed the popover. The transient popover closes on
    /// mouse-down, before the button's action runs on mouse-up; this stops that click reopening it.
    private var closedByButtonClick: Date?
    /// The popover closed because one of our own windows (e.g. All Layouts) was clicked.
    private var closedIntoOwnWindow = false
    /// Whether MacPowertools was already active when the panel opened (e.g. All Layouts or the
    /// editor was key). If so, closing the panel must not deactivate the app.
    private var wasActiveBeforePanel = false

    private let allLayoutsModel = AllLayoutsModel()
    private lazy var allLayouts = AllLayoutsWindowController(model: allLayoutsModel)

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
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        statusItem = item
        setUpPanel()
        setUpAllLayouts()

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

    // MARK: Panel

    private func setUpPanel() {
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(rootView: MenuPanelView(model: panel))
        // Resize the popover when the content's height changes while open (e.g. the monitor picker appears).
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.delegate = self

        panel.onSelectMonitor = { [weak self] id in
            self?.panel.selectedMonitorID = id
            self?.refreshPanel()
        }
        panel.onApplyTile = { [weak self] id in
            guard let self, let display = self.selectedDisplay() else { return }
            self.mutate { $0.apply(id, forDisplay: display) }
        }
        panel.onNewLayout = { [weak self] in self?.openEditorFromPanel(mode: .new) }
        panel.onEditCurrent = { [weak self] in self?.openEditorFromPanel(mode: .editCurrent) }
        panel.onAllLayouts = { [weak self] in
            guard let self else { return }
            self.closePanelKeepingActive()
            self.refreshAllLayouts()
            self.allLayouts.show()
        }
        panel.onToggleSwitcher = { [weak self] in
            self?.toggleWindowSwitcher()
            self?.refreshPanel()
        }
        panel.onToggleLaunch = { [weak self] in
            self?.toggleLaunchAtLogin()
            self?.refreshPanel()
        }
        panel.onOpenPermissionSettings = { Accessibility.openSettingsPane() }
        panel.onQuit = { NSApp.terminate(nil) }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        if let closed = closedByButtonClick {
            closedByButtonClick = nil
            if Date().timeIntervalSince(closed) < 1 { return }
        }
        guard let button = statusItem?.button else { return }
        // Retries the hotkey if it couldn't start earlier (e.g. permission granted since).
        switcher.start()
        panel.selectedMonitorID = pointerMonitorID()
        refreshPanel()
        wasActiveBeforePanel = NSApp.isActive
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.popover.isShown,
                  event.window === self.popover.contentViewController?.view.window else { return event }
            self.popover.performClose(nil)
            return nil
        }
    }

    func popoverWillClose(_ notification: Notification) {
        // Runs while the closing event is current: note what was clicked, if anything.
        closedByButtonClick = nil
        closedIntoOwnWindow = false
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              let window = event.window,
              window !== popover.contentViewController?.view.window else { return }
        if window === statusItem?.button?.window {
            // Only a left click reaches the button's action, so only it should be swallowed.
            if event.type == .leftMouseDown { closedByButtonClick = Date() }
        } else {
            closedIntoOwnWindow = true
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // A late close callback after a quick reopen must not tear down the new session.
        guard !popover.isShown else { return }
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        // Hand focus back to the previous app, unless the user went to one of our windows
        // or the app was already active when the panel opened.
        if !keepActiveOnClose && !closedIntoOwnWindow && !wasActiveBeforePanel { NSApp.deactivate() }
        wasActiveBeforePanel = false
        keepActiveOnClose = false
        closedIntoOwnWindow = false
    }

    private func closePanelKeepingActive() {
        guard popover.isShown else { return }
        keepActiveOnClose = true
        popover.performClose(nil)
    }

    private func openEditorFromPanel(mode: EditorMode) {
        guard let id = selectedDisplay(), let screen = screen(for: id) else { return }
        closePanelKeepingActive()
        openEditor(for: screen, mode: mode)
    }

    /// The monitor under the pointer, else the first.
    private func pointerMonitorID() -> String? {
        let monitors = ScreenIdentity.monitors()
        let point = NSEvent.mouseLocation
        return (monitors.first { NSMouseInRect(point, $0.screen.frame, false) } ?? monitors.first)?.info.id
    }

    /// The panel's selected monitor, if it still exists.
    private func selectedDisplay() -> String? {
        guard let id = panel.selectedMonitorID,
              ScreenIdentity.monitors().contains(where: { $0.info.id == id }) else { return nil }
        return id
    }

    /// Refills the panel from `state`. Falls back to the pointer's monitor if the selected one is gone.
    private func refreshPanel() {
        let monitors = ScreenIdentity.monitors().map(\.info)
        panel.monitors = monitors
        if !monitors.contains(where: { $0.id == panel.selectedMonitorID }) {
            panel.selectedMonitorID = pointerMonitorID()
        }
        if let display = panel.selectedMonitorID {
            panel.tiles = state.panelTiles(forDisplay: display)
            panel.activePresetID = state.activePreset(forDisplay: display).id
        } else {
            panel.tiles = []
            panel.activePresetID = nil
        }
        panel.permissionNeeded = permissionNeeded
        panel.switcherOn = switcher.isEnabled
        panel.launch = LaunchAtLogin.isEnabled ? .on : (LaunchAtLogin.needsApproval ? .needsApproval : .off)
    }

    // MARK: All Layouts

    private func setUpAllLayouts() {
        allLayoutsModel.onToggleFavourite = { [weak self] id in
            self?.mutate { $0.setFavourite(id, !$0.isFavourite(id)) }
        }
        allLayoutsModel.onRename = { [weak self] id, name in
            guard let self, !self.isBeingEdited(id) else { return }
            self.mutate { $0.rename(id, to: name) }
        }
        allLayoutsModel.onDelete = { [weak self] id in self?.deletePreset(id) }
        allLayoutsModel.onRestoreStarters = { [weak self] in
            self?.mutate { $0.restoreStarters() }
        }
        refreshAllLayouts()
    }

    private func refreshAllLayouts() {
        allLayoutsModel.presets = state.presets
        allLayoutsModel.favourites = state.favourites
        allLayoutsModel.lockedPresetID = editor?.mode == .editCurrent ? editor?.presetID : nil
    }

    private func deletePreset(_ id: UUID) {
        guard state.presets.count > 1, !isBeingEdited(id),
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
        refreshPanel()
        refreshAllLayouts()
        guard canSave else { return }
        do { try store.save(state) } catch { showError("Couldn't save presets", error) }
    }

    func activePreset(for screen: NSScreen) -> Preset {
        state.activePreset(forDisplay: ScreenIdentity.uuid(for: screen))
    }

    private func screen(for monitorID: String) -> NSScreen? {
        ScreenIdentity.monitors().first { $0.info.id == monitorID }?.screen
    }

    // MARK: Editor

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
    private var editor: EditorSession? {
        didSet { refreshAllLayouts() }
    }

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
            // Deleted from All Layouts while being edited: don't silently bring it back.
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
            state.touchRecent(preset.id, forDisplay: display)
        }
    }

    /// The preset being edited in place, which can't be renamed or deleted meanwhile.
    private func isBeingEdited(_ id: UUID) -> Bool {
        editor?.mode == .editCurrent && editor?.presetID == id
    }

    /// Refreshes the panel, and cancels the editor if its screen went away or changed geometry.
    @objc private func screenParametersChanged() {
        refreshPanel()
        guard let editor else { return }
        let screen = NSScreen.screens.first { ScreenIdentity.uuid(for: $0) == editor.display }
        if screen?.frame != editor.screenFrame {
            editor.controller.cancel()
            self.editor = nil
        }
    }

    // MARK: Actions

    private func toggleLaunchAtLogin() {
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

    private func toggleWindowSwitcher() {
        switcher.isEnabled.toggle()
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
