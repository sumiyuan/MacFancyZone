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
    /// Retries the hotkey every 2 s while it couldn't start (e.g. until Accessibility is
    /// granted) and the switcher is enabled.
    private var retryTimer: Timer?
    /// While the panel is shown, polls the modifiers in case Option's release was missed.
    private var watchdogTimer: Timer?

    /// The open switcher's windows and selection; nil until the panel is shown.
    private var windows: [SwitcherWindow] = []
    private var selection: SwitcherSelection?
    /// Bumped on every open, commit, and cancel, so a deferred open that's been
    /// overtaken does nothing.
    private var generation = 0
    /// Net moves (next minus previous) received before the deferred open ran.
    private var pendingMoves = 0
    /// True between an `.open` and its deferred block running.
    private var openPending = false
    /// A commit arrived while the open was still pending (a quick flick): the deferred
    /// open switches straight to the selection without showing the panel.
    private var pendingCommit = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                startHotkey()
            } else {
                stopRetrying()
                hotkey.stop()
                machine.reset()
                close()
            }
        }
    }

    init(onPermissionProblem: @escaping () -> Void) {
        self.onPermissionProblem = onPermissionProblem
        panel.onRowClicked = { [weak self] index in self?.rowClicked(index) }
        panel.onRowHovered = { [weak self] index in self?.rowHovered(index) }
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
            hotkeyStarted()
        } else {
            startFailed = true
            onPermissionProblem()
            startRetrying()
        }
    }

    private func hotkeyStarted() {
        stopRetrying()
        if startFailed {
            startFailed = false
            onPermissionRestored?()
        }
    }

    private func startRetrying() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated { self?.retryHotkey() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func retryHotkey() {
        guard isEnabled, startFailed else {
            stopRetrying()
            return
        }
        if hotkey.isRunning || hotkey.start() { hotkeyStarted() }
    }

    // MARK: - Keys

    private func handle(_ input: KeyInput, _ modifiers: Modifiers) -> KeyAction {
        let action = machine.handle(input, modifiers: modifiers)
        switch action {
        case .open(let reverse):
            generation += 1
            pendingMoves = 0
            pendingCommit = false
            openPending = true
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
        guard opened == generation, openPending else { return }
        openPending = false
        let committed = pendingCommit
        pendingCommit = false
        guard machine.isOpen || committed else { return }
        let ordered = focusTracker.ordered(WindowCatalog.currentWindows())
        var newSelection = SwitcherSelection(count: ordered.count, reverse: reverse)
        for _ in 0..<abs(pendingMoves) {
            if pendingMoves > 0 { newSelection.next() } else { newSelection.previous() }
        }
        pendingMoves = 0

        if committed {
            // Quick flick: Option was released before the panel could show.
            let target = newSelection.index.flatMap { ordered.indices.contains($0) ? ordered[$0] : nil }
            close()
            if let target { activateLater(target) }
            return
        }
        guard !ordered.isEmpty, let screen = Self.screenUnderMouse() else {
            machine.reset()
            close()
            return
        }
        windows = ordered
        selection = newSelection
        panel.show(ordered, highlighted: newSelection.index ?? 0, on: screen)
        startWatchdog()
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
        if openPending && selection == nil {
            // The deferred open hasn't run yet: let it switch without showing the panel.
            pendingCommit = true
            return
        }
        let target = selection?.index.flatMap { windows.indices.contains($0) ? windows[$0] : nil }
        close()
        // No windows: nothing to switch to.
        guard let target else { return }
        activateLater(target)
    }

    /// Commit can run from the tap callback: activation makes AX calls that can block on
    /// a busy app, which would stall all input, so do it on the next run-loop turn.
    private func activateLater(_ target: SwitcherWindow) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { _ = WindowActivator.activate(target) }
        }
    }

    /// The hovered row becomes the selection, so releasing Option switches to it.
    private func rowHovered(_ index: Int) {
        guard var current = selection, windows.indices.contains(index) else { return }
        current.select(index)
        selection = current
        panel.setHighlighted(index)
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
        openPending = false
        pendingCommit = false
        stopWatchdog()
        windows = []
        selection = nil
        panel.hide()
    }

    // MARK: - Watchdog

    /// Every 250 ms while the panel is shown, commits if Option is no longer held
    /// (its flagsChanged event was missed).
    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated { self?.checkModifiers() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func checkModifiers() {
        guard machine.isOpen else {
            stopWatchdog()
            return
        }
        let modifiers = SwitcherHotkey.modifiers(CGEventSource.flagsState(.combinedSessionState))
        if !modifiers.option {
            _ = handle(.modifiersChanged, modifiers)
        }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
}
