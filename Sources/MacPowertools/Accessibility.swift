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
