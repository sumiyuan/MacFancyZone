import CoreGraphics

/// Decides when the zone overlay is shown during a window drag: only while Shift is held
/// and the dragged window has actually moved since mouse-down.
public struct DragSnapTracker: Sendable {
  private enum Phase: Sendable {
    case idle
    case pressed(origin: CGPoint)
    case moved
  }

  private var phase: Phase = .idle
  private var shiftHeld = false

  public init() {}

  /// Origin must change by more than this on either axis to count as moved.
  public static let moveThreshold: CGFloat = 1

  public var overlayVisible: Bool {
    if case .moved = phase { return shiftHeld }
    return false
  }

  /// `windowOrigin`: the AX origin of the window under the cursor at mouse-down, or nil if there isn't one.
  public mutating func mouseDown(windowOrigin: CGPoint?) {
    shiftHeld = false
    if let windowOrigin {
      phase = .pressed(origin: windowOrigin)
    } else {
      phase = .idle
    }
  }

  /// Call on every left-mouse-dragged and flags-changed event. `currentWindowOrigin` is called only while
  /// a window drag is in progress, Shift is held, and movement isn't yet confirmed.
  public mutating func update(shiftHeld: Bool, currentWindowOrigin: () -> CGPoint?) {
    guard case .idle = phase else {
      self.shiftHeld = shiftHeld
      if shiftHeld, case .pressed(let origin) = phase,
        let current = currentWindowOrigin(),
        abs(current.x - origin.x) > Self.moveThreshold
          || abs(current.y - origin.y) > Self.moveThreshold
      {
        phase = .moved
      }
      return
    }
    self.shiftHeld = false
  }

  /// Returns true if the caller should snap (the overlay was visible at release). Always resets to idle.
  public mutating func mouseUp() -> Bool {
    let snap = overlayVisible
    phase = .idle
    shiftHeld = false
    return snap
  }
}
