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

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copy(element, attribute).value,
              CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as! CFString as String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copy(element, attribute).value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
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
    /// Seconds an app may take to answer before it contributes no windows.
    static let perAppTimeout: Float = 0.1

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
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { continue }
            let window = item as! AXUIElement
            AXUIElementSetMessagingTimeout(window, perAppTimeout)
            guard SwitcherAX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            let title = SwitcherAX.string(window, kAXTitleAttribute) ?? ""
            result.append(SwitcherWindow(
                key: WindowKey(element: window),
                pid: pid,
                title: title.isEmpty ? appName : title,
                appName: appName,
                icon: icon,
                isMinimized: SwitcherAX.bool(window, kAXMinimizedAttribute) ?? false,
                appIsHidden: hidden
            ))
        }
        return result
    }
}
