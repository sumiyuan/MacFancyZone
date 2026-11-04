import AppKit
import ZonesCore

/// Watches global mouse and modifier events and snaps the dragged window into a zone
/// when it's dropped while Shift is held.
@MainActor
final class DragMonitor {
    private weak var controller: AppController?
    private let overlay = OverlayWindow()
    private var tracker = DragSnapTracker()
    private var monitor: Any?

    /// The window under the cursor at mouse-down.
    private var window: AXWindow?
    /// Its size at mouse-down. A drag that changes the size is a resize (e.g. from the
    /// left or top edge, which also moves the origin), not a move, and must not snap.
    private var initialSize: CGSize?
    /// When the tracker last read the window's origin via AX, for throttling.
    private var lastOriginRead: TimeInterval = 0

    /// Minimum seconds between AX reads while waiting for the window to move.
    private static let originReadInterval: TimeInterval = 0.03
    /// A size change larger than this (points, either axis) marks the drag as a resize.
    private static let sizeTolerance: CGFloat = 1

    /// Zone geometry for the screen under the cursor, computed once per shown screen.
    private struct ScreenZones {
        let screen: NSScreen
        let layout: LayoutNode
        let frame: CGRect          // visible frame, top-left global
        let gappedRects: [CGRect]  // top-left global (AX space)
    }
    private var zones: ScreenZones?
    private var highlighted: Int?

    init(controller: AppController) {
        self.controller = controller
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            let type = event.type
            let flags = event.modifierFlags
            // Global monitor handlers are delivered on the main thread.
            MainActor.assumeIsolated {
                self?.handle(type, flags)
            }
        }
    }

    private func handle(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags) {
        switch type {
        case .leftMouseDown:
            mouseDown()
        case .leftMouseDragged, .flagsChanged:
            update(shiftHeld: flags.contains(ZoneKeys.snapModifier))
        case .leftMouseUp:
            mouseUp()
        default:
            break
        }
    }

    private func mouseDown() {
        endOverlay()
        window = cursorTopLeft().flatMap { AXWindow.under($0) }
        var origin = window?.origin
        initialSize = origin == nil ? nil : window?.size
        if initialSize == nil {
            origin = nil
            window = nil
        }
        lastOriginRead = 0
        tracker.mouseDown(windowOrigin: origin)
    }

    private func update(shiftHeld: Bool) {
        tracker.update(shiftHeld: shiftHeld) { currentOriginIfMoved() }
        guard tracker.overlayVisible else {
            endOverlay()
            return
        }
        updateOverlay()
    }

    /// For the tracker's lazy move check. Returns nil ("not moved yet") when throttled,
    /// when the window can't be read, or when its size changed (a resize, not a move).
    private func currentOriginIfMoved() -> CGPoint? {
        guard let window, let initialSize else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastOriginRead >= Self.originReadInterval else { return nil }
        lastOriginRead = now
        guard let size = window.size,
              abs(size.width - initialSize.width) <= Self.sizeTolerance,
              abs(size.height - initialSize.height) <= Self.sizeTolerance else { return nil }
        return window.origin
    }

    private func mouseUp() {
        let snap = tracker.mouseUp()
        let target = window
        let index = highlighted
        let rects = zones?.gappedRects
        window = nil
        initialSize = nil
        endOverlay()

        guard snap, let target, let index, let rects, rects.indices.contains(index) else { return }
        if target.setFrame(rects[index]) == .apiDisabled {
            controller?.noteAXWriteDisabled()
        }
        // Other errors (fixed-size windows, etc.) are ignored.
    }

    private func updateOverlay() {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) })
                ?? zones?.screen else { return }

        if zones?.screen != screen {
            guard let controller else { return }
            let preset = controller.activePreset(for: screen)
            let frame = ZoneGeometry.flipped(screen.visibleFrame, primaryScreenHeight: primaryHeight)
            let gapped = ZoneGeometry.zoneRects(for: preset.layout, in: frame,
                                                spacing: preset.spacing, outerGap: preset.outerGap)
            let z = ScreenZones(screen: screen, layout: preset.layout, frame: frame, gappedRects: gapped)
            zones = z
            highlighted = hitIndex(location, z, primaryHeight)
            overlay.show(on: screen,
                         zoneRects: gapped.map { ZoneGeometry.flipped($0, primaryScreenHeight: primaryHeight) },
                         highlighted: highlighted)
            return
        }

        guard let z = zones else { return }
        highlighted = hitIndex(location, z, primaryHeight)
        overlay.setHighlighted(highlighted)
    }

    private func hitIndex(_ appKitPoint: CGPoint, _ z: ScreenZones, _ primaryHeight: CGFloat) -> Int? {
        let point = ZoneGeometry.flipped(appKitPoint, primaryScreenHeight: primaryHeight)
        return ZoneGeometry.zoneIndex(at: point, layout: z.layout, in: z.frame)
    }

    private func endOverlay() {
        zones = nil
        highlighted = nil
        overlay.hide()
    }

    private func cursorTopLeft() -> CGPoint? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return ZoneGeometry.flipped(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
    }
}
