import AppKit
import ApplicationServices
import SwitcherCore

/// Records which windows and apps were focused most recently, so the switcher can
/// list windows in recency order.
@MainActor
final class FocusTracker {
    /// Most recent 200 windows. Not pruned to the catalog: windows on other Spaces or of
    /// an app that timed out keep their history.
    private(set) var windowRecency = RecencyList<WindowKey>(capacity: FocusTracker.windowCapacity)
    private(set) var appRecency = RecencyList<Int32>()

    /// One observer per running regular app, keyed by pid.
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    private static let windowNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    private static let windowCapacity = 200
    /// Most tracked-but-absent windows checked for destruction per `ordered` call.
    private static let staleChecksPerOrdering = 8

    /// Lives for the app's lifetime (owned by `SwitcherController`), so it never
    /// removes its observers.
    init() {}

    /// Observes workspace app changes and AX focus changes, and seeds the trackers
    /// with the frontmost app and its focused window.
    func start() {
        guard workspaceTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                let pid = app.processIdentifier
                let isRegular = app.activationPolicy == .regular
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.workspaceEvent(name, pid: pid, isRegular: isRegular)
                }
            }
            workspaceTokens.append(token)
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            addObserver(for: app.processIdentifier)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            appActivated(front.processIdentifier, isRegular: front.activationPolicy == .regular)
        }
    }

    /// `windows` in recency order. Recency isn't pruned to `windows` (which may miss other
    /// Spaces' windows); instead a few tracked windows absent from `windows` are checked
    /// and dropped if they no longer exist.
    func ordered(_ windows: [SwitcherWindow]) -> [SwitcherWindow] {
        dropDestroyedWindows(absentFrom: Set(windows.map(\.key)))

        let candidates = windows.map { WindowCandidate(key: $0.key, appPID: $0.pid) }
        let byKey = Dictionary(windows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return RecencyOrdering.order(candidates, windows: windowRecency, apps: appRecency)
            .compactMap { byKey[$0] }
    }

    // MARK: - Events

    private func workspaceEvent(_ name: Notification.Name, pid: pid_t, isRegular: Bool) {
        switch name {
        case NSWorkspace.didActivateApplicationNotification:
            // Retry here too: right after launch an app may not accept AX observers yet.
            if isRegular { addObserver(for: pid) }
            appActivated(pid, isRegular: isRegular)
        case NSWorkspace.didLaunchApplicationNotification:
            if isRegular { addObserver(for: pid) }
        case NSWorkspace.didTerminateApplicationNotification:
            appTerminated(pid)
        default:
            break
        }
    }

    private func appActivated(_ pid: pid_t, isRegular: Bool) {
        guard isRegular else { return }
        appRecency.touch(pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, WindowCatalog.perAppTimeout)
        if let window = SwitcherAX.element(appElement, kAXFocusedWindowAttribute) {
            windowRecency.touch(WindowKey(element: window))
        }
    }

    private func appTerminated(_ pid: pid_t) {
        removeObserver(for: pid)
        appRecency.remove(pid)
        windowRecency.prune(keeping: Set(windowRecency.items.filter { key in
            var owner: pid_t = 0
            return AXUIElementGetPid(key.element, &owner) == .success && owner != pid
        }))
    }

    /// Checks up to `staleChecksPerOrdering` tracked windows not in `present`, most
    /// recent first, and drops those whose element is gone.
    private func dropDestroyedWindows(absentFrom present: Set<WindowKey>) {
        let absent = windowRecency.items.lazy.filter { !present.contains($0) }
            .prefix(Self.staleChecksPerOrdering)
        for key in Array(absent) {
            AXUIElementSetMessagingTimeout(key.element, WindowCatalog.perAppTimeout)
            if SwitcherAX.copy(key.element, kAXRoleAttribute).error == .invalidUIElement {
                windowRecency.remove(key)
            }
        }
    }

    /// From the AX callback: only the frontmost app's focus changes count, so a
    /// background app changing its own focused window doesn't jump the list.
    fileprivate func windowFocused(_ window: WindowKey) {
        var owner: pid_t = 0
        guard AXUIElementGetPid(window.element, &owner) == .success,
              owner == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        windowRecency.touch(window)
    }

    // MARK: - AX observers

    /// Callers pass only regular apps.
    private func addObserver(for pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              observers[pid] == nil else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, focusTrackerCallback, &created) == .success,
              let observer = created else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, WindowCatalog.perAppTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = false
        for name in Self.windowNotifications {
            if AXObserverAddNotification(observer, appElement, name as CFString, refcon) == .success {
                registered = true
            }
        }
        guard registered else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

/// AX observer callback. Sources are on the main run loop, so this runs on the main thread.
/// `refcon` is an unretained `FocusTracker`, which lives for the app's lifetime.
private func focusTrackerCallback(_ observer: AXObserver,
                                  _ element: AXUIElement,
                                  _ notification: CFString,
                                  _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let address = UInt(bitPattern: refcon)
    let window = WindowKey(element: element)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let tracker = Unmanaged<FocusTracker>.fromOpaque(pointer).takeUnretainedValue()
        tracker.windowFocused(window)
    }
}
