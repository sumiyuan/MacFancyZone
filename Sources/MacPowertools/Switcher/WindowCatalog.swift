import AppKit
import ApplicationServices

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

    /// Standard windows of regular apps (not this process), in enumeration order:
    /// apps in `runningApplications` order, each app's windows in AX order.
    static func currentWindows() -> [SwitcherWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [SwitcherWindow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            result += windows(of: app)
        }
        return result
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
