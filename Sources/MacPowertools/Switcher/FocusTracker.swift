import AppKit
import ApplicationServices
import SwitcherCore

/// Records which windows and apps were focused most recently, so the switcher can
/// list windows in recency order.
@MainActor
final class FocusTracker {
    private(set) var windowRecency = RecencyList<WindowKey>()
    private(set) var appRecency = RecencyList<Int32>()

    /// One observer per running regular app, keyed by pid.
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    private static let windowNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    init() {}

    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        for pid in Array(observers.keys) { removeObserver(for: pid) }
    }

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
            appActivated(front.processIdentifier)
        }
    }

    /// `windows` in recency order. Prunes both recency lists to the windows in `windows`
    /// and the apps still running before ordering.
    func ordered(_ windows: [SwitcherWindow]) -> [SwitcherWindow] {
        windowRecency.prune(keeping: Set(windows.map(\.key)))
        appRecency.prune(keeping: Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)))

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
            appActivated(pid)
        case NSWorkspace.didLaunchApplicationNotification:
            if isRegular { addObserver(for: pid) }
        case NSWorkspace.didTerminateApplicationNotification:
            appTerminated(pid)
        default:
            break
        }
    }

    private func appActivated(_ pid: pid_t) {
        appRecency.touch(pid)
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, WindowCatalog.perAppTimeout)
        if let window = SwitcherAX.element(appElement, kAXFocusedWindowAttribute) {
            windowRecency.touch(WindowKey(element: window))
        }
    }

    private func appTerminated(_ pid: pid_t) {
        removeObserver(for: pid)
        appRecency.prune(keeping: Set(appRecency.items.filter { $0 != pid }))
        windowRecency.prune(keeping: Set(windowRecency.items.filter { key in
            var owner: pid_t = 0
            return AXUIElementGetPid(key.element, &owner) == .success && owner != pid
        }))
    }

    fileprivate func windowFocused(_ window: WindowKey) {
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
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// AX observer callback. Sources are on the main run loop, so this runs on the main thread.
/// `refcon` is an unretained `FocusTracker`; the tracker removes its observers in deinit.
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
