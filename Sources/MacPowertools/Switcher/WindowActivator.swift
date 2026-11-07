import AppKit
import ApplicationServices

/// Brings a catalogued window to the front, un-minimizing and unhiding as needed.
@MainActor
enum WindowActivator {
    /// Order: unhide the app if hidden, set kAXMinimized false if minimized, AXRaise,
    /// set kAXMain true, then NSRunningApplication.activate(). If activation is refused
    /// (cooperative activation), falls back to setting kAXFrontmost on the app.
    /// Returns false if the window is gone.
    @discardableResult
    static func activate(_ window: SwitcherWindow) -> Bool {
        let element = window.key.element
        AXUIElementSetMessagingTimeout(element, WindowCatalog.perAppTimeout)
        // A window that no longer answers its role has been closed (or its app quit).
        guard SwitcherAX.string(element, kAXRoleAttribute).value != nil else { return false }

        let app = NSRunningApplication(processIdentifier: window.pid)
        if let app, app.isHidden {
            app.unhide()
        }
        if SwitcherAX.bool(element, kAXMinimizedAttribute).value ?? window.isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if app?.activate() != true {
            // This app is an inactive accessory app, so macOS 14+ may refuse the request.
            let appElement = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(appElement, WindowCatalog.perAppTimeout)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        return true
    }
}
