import AppKit

/// Non-activating Option+Tab panel listing windows, one row each.
@MainActor
final class SwitcherPanel {
    var onRowClicked: ((Int) -> Void)?

    private static let width: CGFloat = 520
    private static let rowHeight: CGFloat = 34
    private static let maxRows = 12
    private static let padding: CGFloat = 8

    private let panel: SwitcherNSPanel
    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let listView = SwitcherListView()
    private var highlighted = 0

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = SwitcherNSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Always light text on the dark HUD, whatever the system appearance.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = listView
        effectView.addSubview(scrollView)
        panel.contentView = effectView

        listView.onClick = { [weak self] index in self?.onRowClicked?(index) }
    }

    func show(_ windows: [SwitcherWindow], highlighted index: Int, on screen: NSScreen) {
        highlighted = index
        listView.setRows(windows, highlighted: index)

        let visibleRows = min(windows.count, Self.maxRows)
        let height = CGFloat(visibleRows) * Self.rowHeight + Self.padding * 2
        let size = CGSize(width: Self.width, height: height)
        let area = screen.visibleFrame
        let origin = CGPoint(x: (area.midX - size.width / 2).rounded(),
                             y: (area.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: false)

        effectView.frame = CGRect(origin: .zero, size: size)
        scrollView.frame = effectView.bounds
        let listHeight = CGFloat(windows.count) * Self.rowHeight + Self.padding * 2
        listView.frame = CGRect(x: 0, y: 0, width: Self.width, height: max(listHeight, height))
        listView.layoutRows()
        scrollToHighlighted()
        panel.orderFrontRegardless()
    }

    /// Redraws only the two rows involved and keeps the new one visible.
    func setHighlighted(_ index: Int) {
        guard index != highlighted else { return }
        listView.updateHighlight(from: highlighted, to: index)
        highlighted = index
        scrollToHighlighted()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func scrollToHighlighted() {
        guard let row = listView.rowFrame(at: highlighted) else { return }
        listView.scrollToVisible(row)
    }

    fileprivate static func rowFrame(index: Int, width: CGFloat) -> CGRect {
        CGRect(x: padding, y: padding + CGFloat(index) * rowHeight,
               width: width - padding * 2, height: rowHeight)
    }

    fileprivate static func rowIndex(atY y: CGFloat) -> Int {
        Int(((y - padding) / rowHeight).rounded(.down))
    }
}

private final class SwitcherNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Flipped so row 0 is at the top; handles clicks for all rows.
private final class SwitcherListView: NSView {
    var onClick: ((Int) -> Void)?
    private var rows: [SwitcherRowView] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setRows(_ windows: [SwitcherWindow], highlighted: Int) {
        rows.forEach { $0.removeFromSuperview() }
        rows = windows.enumerated().map { i, window in
            let row = SwitcherRowView(window: window)
            row.isHighlighted = i == highlighted
            addSubview(row)
            return row
        }
    }

    func layoutRows() {
        for (i, row) in rows.enumerated() {
            row.frame = SwitcherPanel.rowFrame(index: i, width: bounds.width)
        }
    }

    func rowFrame(at index: Int) -> CGRect? {
        rows.indices.contains(index) ? rows[index].frame : nil
    }

    func updateHighlight(from old: Int, to new: Int) {
        if rows.indices.contains(old) { rows[old].isHighlighted = false }
        if rows.indices.contains(new) { rows[new].isHighlighted = true }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = SwitcherPanel.rowIndex(atY: point.y)
        guard rows.indices.contains(index) else { return }
        onClick?(index)
    }
}

private final class SwitcherRowView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let appField = NSTextField(labelWithString: "")

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            applyHighlight()
        }
    }

    init(window: SwitcherWindow) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7

        iconView.image = window.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.stringValue = window.title
        titleField.font = .systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        appField.stringValue = window.appName
        appField.font = .systemFont(ofSize: 13)
        appField.alignment = .right
        appField.lineBreakMode = .byTruncatingTail
        appField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        for view in [iconView, titleField, appField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            appField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 12),
            appField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            appField.centerYAnchor.constraint(equalTo: centerYAnchor),
            appField.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
        ])
        applyHighlight()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidChangeEffectiveAppearance() {
        applyHighlight()
    }

    private func applyHighlight() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isHighlighted ? NSColor.systemBlue.cgColor : nil
        }
        titleField.textColor = isHighlighted ? .white : .labelColor
        appField.textColor = isHighlighted ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
    }
}
