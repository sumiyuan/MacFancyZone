import AppKit
import SwitcherCore

/// Wires the Option+Tab hotkey, the key machine, the window catalog, and the panel.
@MainActor
final class SwitcherController {
    private static let enabledKey = "windowSwitcherEnabled"

    private let onPermissionProblem: () -> Void
    /// Called when the hotkey starts after an earlier start failed for lack of permission.
    var onPermissionRestored: (() -> Void)?

    private var machine = SwitcherKeyMachine()
    private let focusTracker = FocusTracker()
    private let panel = SwitcherPanel()
    private lazy var hotkey = SwitcherHotkey { [unowned self] input, modifiers in
        self.handle(input, modifiers)
    }
    private var startFailed = false

    /// The open switcher's windows and selection; nil until the panel is shown.
    private var windows: [SwitcherWindow] = []
    private var selection: SwitcherSelection?
    /// Bumped on every open, commit, and cancel, so a deferred open that's been
    /// overtaken does nothing.
    private var generation = 0
    /// Net moves (next minus previous) received before the deferred open ran.
    private var pendingMoves = 0

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                startHotkey()
            } else {
                hotkey.stop()
                machine.reset()
                close()
            }
        }
    }

    init(onPermissionProblem: @escaping () -> Void) {
        self.onPermissionProblem = onPermissionProblem
        panel.onRowClicked = { [weak self] index in self?.rowClicked(index) }
    }

    /// Starts focus tracking and, if enabled and not already running, the hotkey.
    /// Safe to call repeatedly (e.g. each time the menu opens, to retry after a
    /// permission grant).
    func start() {
        focusTracker.start()
        if isEnabled { startHotkey() }
    }

    private func startHotkey() {
        guard !hotkey.isRunning else { return }
        if hotkey.start() {
            if startFailed {
                startFailed = false
                onPermissionRestored?()
            }
        } else {
            startFailed = true
            onPermissionProblem()
        }
    }

    // MARK: - Keys

    private func handle(_ input: KeyInput, _ modifiers: Modifiers) -> KeyAction {
        let action = machine.handle(input, modifiers: modifiers)
        switch action {
        case .open(let reverse):
            generation += 1
            pendingMoves = 0
            let opened = generation
            // Gathering windows can be slow; keep the tap callback quick.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.open(reverse: reverse, generation: opened) }
            }
        case .moveNext:
            move(by: 1)
        case .movePrevious:
            move(by: -1)
        case .commit:
            commit()
        case .cancel:
            close()
        case .passThrough, .swallow:
            break
        }
        return action
    }

    private func open(reverse: Bool, generation opened: Int) {
        guard opened == generation, machine.isOpen else { return }
        // Always the full catalog: `ordered` prunes recency to the windows it's given.
        let ordered = focusTracker.ordered(WindowCatalog.currentWindows())
        guard !ordered.isEmpty, let screen = Self.screenUnderMouse() else {
            machine.reset()
            return
        }
        var newSelection = SwitcherSelection(count: ordered.count, reverse: reverse)
        for _ in 0..<abs(pendingMoves) {
            if pendingMoves > 0 { newSelection.next() } else { newSelection.previous() }
        }
        pendingMoves = 0
        windows = ordered
        selection = newSelection
        panel.show(ordered, highlighted: newSelection.index ?? 0, on: screen)
    }

    private func move(by step: Int) {
        guard var current = selection else {
            pendingMoves += step
            return
        }
        if step > 0 { current.next() } else { current.previous() }
        selection = current
        if let index = current.index { panel.setHighlighted(index) }
    }

    private func commit() {
        let target = selection?.index.flatMap { windows.indices.contains($0) ? windows[$0] : nil }
        close()
        // Nothing shown yet (deferred open pending, or no windows): nothing to switch to.
        guard let target else { return }
        // Runs from the tap callback: activation makes AX calls that can block on a busy
        // app, which would stall all input, so do it on the next run-loop turn.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { _ = WindowActivator.activate(target) }
        }
    }

    private func rowClicked(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        let target = windows[index]
        machine.reset()
        close()
        WindowActivator.activate(target)
    }

    /// Hides the panel and forgets the open switcher's state. Doesn't touch the machine.
    private func close() {
        generation += 1
        pendingMoves = 0
        windows = []
        selection = nil
        panel.hide()
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
}
