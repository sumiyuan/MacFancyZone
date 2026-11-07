import AppKit
import ApplicationServices
import SwitcherCore

/// AXUIElement identity, compared with CFEqual and hashed with CFHash.
struct WindowKey: Hashable, @unchecked Sendable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// One switchable window, snapshotted when the catalog was read.
struct SwitcherWindow {
    let key: WindowKey
    let pid: pid_t
    let title: String          // app name if the AX title is empty
    let appName: String
    let icon: NSImage?
    let isMinimized: Bool
    let appIsHidden: Bool
}

/// Small AX attribute helpers shared by the switcher files.
enum SwitcherAX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error == .success ? value : nil, error)
    }

    /// The string value (nil if absent or not a string) and the call's error.
    static func string(_ element: AXUIElement, _ attribute: String) -> (value: String?, error: AXError) {
        let (value, error) = copy(element, attribute)
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else { return (nil, error) }
        return (value as! CFString as String, error)
    }

    /// The boolean value (nil if absent or not a boolean) and the call's error.
    static func bool(_ element: AXUIElement, _ attribute: String) -> (value: Bool?, error: AXError) {
        let (value, error) = copy(element, attribute)
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return (nil, error) }
        return (CFBooleanGetValue((value as! CFBoolean)), error)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute).value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

/// Enumerates the windows the switcher can offer, via the Accessibility API.
@MainActor
enum WindowCatalog {
    /// Seconds a single AX call to an app may block. If the first call (`kAXWindows`)
    /// fails or times out, the app contributes no windows.
    static let perAppTimeout: Float = 0.1

    /// Total time one app may cost; once spent, the app's remaining windows are skipped.
    static let perAppBudget: Duration = .milliseconds(150)

    /// Highest AX element ID tried when searching an app for windows on other desktops.
    static let maxElementID: UInt64 = 1000
    /// Time the search may spend on one app per catalog read.
    static let searchBudget: Duration = .milliseconds(150)

    /// Every window found so far (on any desktop) and which window IDs were searched for, per app.
    private static var offSpaceIndex = OffSpaceIndex<AXUIElement>()

    /// Standard windows of regular apps (not this process), in enumeration order:
    /// apps in `runningApplications` order, each app's windows on this desktop in AX
    /// order, then its windows on other desktops and in full screen.
    static func currentWindows() -> [SwitcherWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let systemIDs = systemWindowIDs()
        var result: [SwitcherWindow] = []
        var pids = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            pids.insert(app.processIdentifier)
            let here = windows(of: app)
            result += here
            if PrivateAX.isAvailable {
                result += otherDesktopWindows(of: app, here: here,
                                              systemIDs: systemIDs[app.processIdentifier] ?? [])
            }
        }
        offSpaceIndex.retain(pids: pids)
        return result
    }

    /// Normal-layer window IDs on every desktop, by owning app.
    private static func systemWindowIDs() -> [pid_t: Set<CGWindowID>] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var byPID: [pid_t: Set<CGWindowID>] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            byPID[pid, default: []].insert(id)
        }
        return byPID
    }

    /// The app's standard windows that normal Accessibility can't see because they're on
    /// another desktop or in full screen. New window IDs are searched for by walking the
    /// app's AX element IDs; results are remembered so each window is searched for once.
    private static func otherDesktopWindows(of app: NSRunningApplication, here: [SwitcherWindow],
                                            systemIDs: Set<CGWindowID>) -> [SwitcherWindow] {
        let pid = app.processIdentifier
        offSpaceIndex.prune(pid: pid, systemWindowIDs: systemIDs)
        var visible = Set<CGWindowID>()
        for window in here {
            guard let id = PrivateAX.windowID(of: window.key.element) else { continue }
            visible.insert(id)
            offSpaceIndex.remember(pid: pid, id: id, element: window.key.element)
        }

        let missing = offSpaceIndex.missing(pid: pid, systemWindowIDs: systemIDs, visibleIDs: visible)
        if !missing.isEmpty {
            let start = ContinuousClock.now
            var found: [CGWindowID: AXUIElement] = [:]
            var completed = true
            for elementID in 0..<maxElementID {
                guard found.count < missing.count else { break }
                guard start.duration(to: .now) < searchBudget else { completed = false; break }
                guard let element = PrivateAX.element(pid: pid, elementID: elementID) else { continue }
                AXUIElementSetMessagingTimeout(element, perAppTimeout)
                guard let id = PrivateAX.windowID(of: element), missing.contains(id), found[id] == nil,
                      SwitcherAX.string(element, kAXSubroleAttribute).value == kAXStandardWindowSubrole
                else { continue }
                found[id] = element
            }
            // An unfinished search records only what it found, so the rest is retried next time.
            offSpaceIndex.recordScan(pid: pid, looked: completed ? missing : Set(found.keys), found: found)
        }
        let known = offSpaceIndex.offDesktop(pid: pid, visibleIDs: visible)

        let appName = app.localizedName ?? ""
        return known.values.compactMap { element in
            AXUIElementSetMessagingTimeout(element, perAppTimeout)
            let title = SwitcherAX.string(element, kAXTitleAttribute)
            guard title.error != .invalidUIElement else { return nil }
            let text = title.value ?? ""
            return SwitcherWindow(
                key: WindowKey(element: element),
                pid: pid,
                title: text.isEmpty ? appName : text,
                appName: appName,
                icon: app.icon,
                isMinimized: SwitcherAX.bool(element, kAXMinimizedAttribute).value ?? false,
                appIsHidden: app.isHidden
            )
        }
    }

    private static func windows(of app: NSRunningApplication) -> [SwitcherWindow] {
        let start = ContinuousClock.now
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, perAppTimeout)
        guard let value = SwitcherAX.copy(appElement, kAXWindowsAttribute).value,
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }

        let appName = app.localizedName ?? ""
        let icon = app.icon
        let hidden = app.isHidden
        var result: [SwitcherWindow] = []
        for item in value as! [AnyObject] {
            // A busy app must not stall the panel: stop once its budget is spent.
            guard start.duration(to: .now) < perAppBudget else { break }
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { continue }
            let window = item as! AXUIElement
            AXUIElementSetMessagingTimeout(window, perAppTimeout)

            let subrole = SwitcherAX.string(window, kAXSubroleAttribute)
            if subrole.error == .cannotComplete { break }
            guard subrole.value == kAXStandardWindowSubrole else { continue }
            let title = SwitcherAX.string(window, kAXTitleAttribute)
            if title.error == .cannotComplete { break }
            let minimized = SwitcherAX.bool(window, kAXMinimizedAttribute)
            if minimized.error == .cannotComplete { break }

            let text = title.value ?? ""
            result.append(SwitcherWindow(
                key: WindowKey(element: window),
                pid: pid,
                title: text.isEmpty ? appName : text,
                appName: appName,
                icon: icon,
                isMinimized: minimized.value ?? false,
                appIsHidden: hidden
            ))
        }
        return result
    }
}

