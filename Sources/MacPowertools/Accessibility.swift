import AppKit
import ApplicationServices

/// Accessibility (AX) permission helpers. Moving other apps' windows needs it.
enum Accessibility {
    /// Whether this process is trusted for Accessibility.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Opens System Settings at Privacy & Security > Accessibility.
    @MainActor
    static func openSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// A window owned by another app, addressed through the Accessibility API.
/// Coordinates are top-left global (AX/CG space).
struct AXWindow {
    let element: AXUIElement

    /// Seconds an AX call may block on an unresponsive app before failing.
    private static let messagingTimeout: Float = 0.25

    /// The window under `point` (top-left global), or nil if there isn't one or it belongs to this process.
    static func under(_ point: CGPoint) -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let window: AXUIElement
        if let role = copyAttribute(hit, kAXRoleAttribute) as? String, role == kAXWindowRole {
            window = hit
        } else if let value = copyAttribute(hit, kAXWindowAttribute),
                  CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = value as! AXUIElement
        } else {
            return nil
        }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return AXWindow(element: window)
    }

    /// `kAXPositionAttribute`: the window's top-left corner, top-left global.
    var origin: CGPoint? {
        guard let value = Self.copyAttribute(element, kAXPositionAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Sets position, then size, then position again (a size change can be clamped
    /// against the old position). Returns the first non-success error, or `.success`.
    func setFrame(_ rect: CGRect) -> AXError {
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return .failure }
        let results = [
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position),
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue),
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position),
        ]
        return results.first { $0 != .success } ?? .success
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
