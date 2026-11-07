import ApplicationServices
import Darwin
import Foundation
import SwitcherCore

/// Undocumented Accessibility functions, loaded at run time so a macOS that drops them
/// degrades to current-desktop windows instead of failing to launch. The same functions
/// AltTab uses to see windows on other desktops and in full screen.
enum PrivateAX {
    private typealias CreateWithToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)

    private static let createWithToken: CreateWithToken? = {
        guard let sym = dlsym(handle, "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(sym, to: CreateWithToken.self)
    }()

    private static let getWindow: GetWindow? = {
        guard let sym = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindow.self)
    }()

    static var isAvailable: Bool { createWithToken != nil && getWindow != nil }

    /// The system window ID behind an AX window element.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id = CGWindowID(0)
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    /// An AX element for `pid` with the given element ID, which may not exist.
    static func element(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let createWithToken else { return nil }
        return createWithToken(RemoteToken.data(pid: pid, elementID: elementID) as CFData)?.takeRetainedValue()
    }
}
