import CoreGraphics

/// Keys used by the window switcher. The shortcut is defined only here.
enum SwitcherKeys {
    static let tab: CGKeyCode = 48, escape: CGKeyCode = 53, up: CGKeyCode = 126, down: CGKeyCode = 125
    /// Held to open the switcher and keep it open; releasing it commits.
    static let modifier: CGEventFlags = .maskAlternate      // Option
}
