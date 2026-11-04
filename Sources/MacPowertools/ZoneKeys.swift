import AppKit

/// Keyboard modifiers used by the zones feature.
enum ZoneKeys {
    /// Held while dragging a window to snap it, and in the editor to switch
    /// the split orientation to horizontal.
    static let snapModifier: NSEvent.ModifierFlags = .shift
}
