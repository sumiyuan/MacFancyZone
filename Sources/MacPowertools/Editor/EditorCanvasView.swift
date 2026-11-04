import AppKit
import ZonesCore

/// Draws the draft layout at true scale over the screen's visible frame and
/// handles split / resize / merge. Coordinates are top-left (`isFlipped`).
///
/// Dividers, the guide line and hit testing all use the *layout frame*: the
/// canvas bounds, inset by the spacing when the outer gap is on. That's the
/// rect `ZoneGeometry.zoneRects` maps unit space into, so handles sit in the
/// middle of the drawn gaps at any spacing.
final class EditorCanvasView: NSView {
    private let draft: EditorDraft

    private enum Hover: Equatable {
        case none
        case zone(path: NodePath, point: CGPoint)   // point in canvas coordinates
        case divider(NodePath)
    }

    private var hover: Hover = .none
    private var dragging: Divider?
    private var horizontalMode = false

    init(draft: EditorDraft) {
        self.draft = draft
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Call after the draft changes.
    func draftDidChange() {
        refreshHover()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: Geometry

    private var layoutFrame: CGRect {
        draft.outerGap ? bounds.insetBy(dx: draft.spacing, dy: draft.spacing) : bounds
    }

    private func toLayout(_ p: CGPoint) -> CGPoint {
        let f = layoutFrame
        return CGPoint(x: p.x - f.minX, y: p.y - f.minY)
    }

    private func hit(_ p: CGPoint) -> EditorHit {
        EditorHitTest.hit(toLayout(p), layout: draft.layout, canvasSize: layoutFrame.size)
    }

    private func canvasRect(unit u: CGRect) -> CGRect {
        let f = layoutFrame
        return CGRect(x: f.minX + u.minX * f.width, y: f.minY + u.minY * f.height,
                      width: u.width * f.width, height: u.height * f.height)
    }

    /// The divider line in canvas coordinates.
    private func lineRect(_ d: Divider) -> CGRect {
        let f = layoutFrame
        switch d.direction {
        case .vertical:
            return CGRect(x: f.minX + d.position * f.width, y: f.minY + d.crossStart * f.height,
                          width: 0, height: d.crossSpan * f.height)
        case .horizontal:
            return CGRect(x: f.minX + d.crossStart * f.width, y: f.minY + d.position * f.height,
                          width: d.crossSpan * f.width, height: 0)
        }
    }

    private func handleRect(_ d: Divider) -> CGRect {
        let line = lineRect(d)
        let size = d.direction == .vertical ? CGSize(width: 8, height: 36) : CGSize(width: 36, height: 8)
        return CGRect(x: line.midX - size.width / 2, y: line.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let layout = draft.layout
        let rects = ZoneGeometry.zoneRects(for: layout, in: bounds, spacing: draft.spacing, outerGap: draft.outerGap)
        let accent = NSColor.systemBlue
        for (i, rect) in rects.enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            accent.withAlphaComponent(0.22).setFill()
            path.fill()
            accent.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 2
            path.stroke()

            let fontSize = max(12, min(64, min(rect.width, rect.height) / 4))
            let label = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }

        if case let .zone(path, point) = hover, dragging == nil,
           let zone = layout.zones().first(where: { $0.path == path }) {
            let r = canvasRect(unit: zone.unitRect)
            let guide = horizontalMode
                ? CGRect(x: r.minX, y: point.y - 1, width: r.width, height: 2)
                : CGRect(x: point.x - 1, y: r.minY, width: 2, height: r.height)
            NSColor.systemYellow.setFill()
            guide.fill()
        }

        let active: NodePath? = dragging?.path ?? { if case let .divider(p) = hover { return p } else { return nil } }()
        for d in layout.dividers() {
            let pill = NSBezierPath(roundedRect: handleRect(d), xRadius: 4, yRadius: 4)
            (d.path == active ? NSColor.white : NSColor.white.withAlphaComponent(0.8)).setFill()
            pill.fill()
        }
    }

    // MARK: Cursor

    override func resetCursorRects() {
        let t = EditorHitTest.dividerTolerance
        for d in draft.layout.dividers() {
            let band = lineRect(d).insetBy(dx: d.direction == .vertical ? -t : 0,
                                           dy: d.direction == .horizontal ? -t : 0)
            addCursorRect(band, cursor: d.direction == .vertical ? .resizeLeftRight : .resizeUpDown)
        }
    }

    // MARK: Hover

    private func setHover(_ new: Hover) {
        guard new != hover else { return }
        hover = new
        needsDisplay = true
    }

    private func updateHover(at p: CGPoint) {
        // Ignore the canvas under the toolbar.
        if let content = window?.contentView,
           content.hitTest(content.convert(p, from: self)) !== self {
            setHover(.none)
            return
        }
        switch hit(p) {
        case let .divider(d): setHover(.divider(d.path))
        case let .zone(path, _): setHover(.zone(path: path, point: p))
        case .none: setHover(.none)
        }
    }

    private func refreshHover() {
        guard let window else { return }
        updateHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func setHorizontalMode(_ flags: NSEvent.ModifierFlags) {
        let on = flags.contains(ZoneKeys.snapModifier)
        guard on != horizontalMode else { return }
        horizontalMode = on
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        setHorizontalMode(event.modifierFlags)
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        setHover(.none)
    }

    override func flagsChanged(with event: NSEvent) {
        setHorizontalMode(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    // MARK: Editing

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        setHorizontalMode(NSEvent.modifierFlags.union(event.modifierFlags))
        switch hit(p) {
        case let .divider(d):
            dragging = d
            needsDisplay = true
        case let .zone(path, local):
            let direction: SplitDirection = horizontalMode ? .horizontal : .vertical
            let ratio = Double(horizontalMode ? local.y : local.x)
            if let next = draft.layout.splitting(zoneAt: path, direction: direction, ratio: ratio) {
                draft.layout = next
            }
        case .none:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let p = toLayout(convert(event.locationInWindow, from: nil))
        let ratio = EditorHitTest.ratio(dragging: d, to: p, canvasSize: layoutFrame.size)
        if let next = draft.layout.resizing(splitAt: d.path, ratio: ratio), next != draft.layout {
            draft.layout = next
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        refreshHover()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard case let .divider(d) = hit(convert(event.locationInWindow, from: nil)) else { return }
        if let next = draft.layout.removingDivider(at: d.path) {
            draft.layout = next
        } else {
            NSSound.beep()
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        // Routes Esc to cancelOperation(_:) up the responder chain (the window).
        interpretKeyEvents([event])
    }
}
