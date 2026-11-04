import AppKit

/// Full-screen, click-through panel that draws the zones during a Shift-drag.
@MainActor
final class OverlayWindow {
    private let panel: NSPanel
    private let view = OverlayView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
    }

    /// `zoneRects` are gapped rects in AppKit global coordinates.
    func show(on screen: NSScreen, zoneRects: [CGRect], highlighted: Int?) {
        let frame = screen.frame
        panel.setFrame(frame, display: false)
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.zoneRects = zoneRects.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        view.highlighted = highlighted
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    /// Redraws only if the value changed, and only the affected zones.
    func setHighlighted(_ index: Int?) {
        guard index != view.highlighted else { return }
        let old = view.highlighted
        view.highlighted = index
        for i in [old, index].compactMap({ $0 }) where view.zoneRects.indices.contains(i) {
            view.setNeedsDisplay(view.zoneRects[i].insetBy(dx: -2, dy: -2))
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

private final class OverlayView: NSView {
    /// Window-local (bottom-left) gapped zone rects, in zone-number order.
    var zoneRects: [CGRect] = []
    var highlighted: Int?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let accent = NSColor.controlAccentColor
        for (i, rect) in zoneRects.enumerated() where rect.intersects(dirtyRect) {
            let isHighlighted = i == highlighted
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            (isHighlighted ? accent.withAlphaComponent(0.45) : NSColor.black.withAlphaComponent(0.25)).setFill()
            path.fill()
            (isHighlighted ? accent : NSColor.white.withAlphaComponent(0.6)).setStroke()
            path.lineWidth = isHighlighted ? 3 : 1.5
            path.stroke()

            let fontSize = max(12, min(64, min(rect.width, rect.height) / 4))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
            let label = NSAttributedString(string: "\(i + 1)", attributes: attrs)
            let size = label.size()
            label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }
}
