import AppKit
import SwiftUI
import ZonesCore

/// Borderless windows can't become key unless they say so.
private final class EditorWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Full-screen layout editor for one monitor.
@MainActor
final class EditorWindowController {
    private let window: EditorWindow
    private let draft: EditorDraft
    private let canvas: EditorCanvasView
    private let onSave: (Preset) -> Void
    /// Called once, asynchronously, after the editor closes (after save or cancel).
    var onClose: (() -> Void)?
    private var closed = false

    /// The draft is a copy. onSave gets the edited preset; cancel discards it.
    init(screen: NSScreen, draft preset: Preset, onSave: @escaping (Preset) -> Void) {
        self.onSave = onSave
        draft = EditorDraft(preset)
        canvas = EditorCanvasView(draft: draft)

        let frame = screen.frame
        let visible = screen.visibleFrame
        window = EditorWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrame(frame, display: false)

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        window.contentView = content

        // The content view is bottom-left; place the canvas over the visible frame.
        canvas.frame = CGRect(x: visible.minX - frame.minX, y: visible.minY - frame.minY,
                              width: visible.width, height: visible.height)
        content.addSubview(canvas)

        let toolbar = NSHostingView(rootView: EditorToolbar(
            draft: draft,
            onCancel: { [weak self] in self?.cancel() },
            onSave: { [weak self] in self?.save() }))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: visible.midX - frame.minX),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: frame.maxY - visible.maxY + 16),
        ])

        window.initialFirstResponder = canvas
        window.onCancel = { [weak self] in self?.cancel() }
        draft.onChange = { [weak canvas] in canvas?.draftDidChange() }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private func save() {
        guard !draft.trimmedName.isEmpty else { return }
        let preset = draft.preset
        close()
        onSave(preset)
    }

    /// Closes the editor and discards the draft.
    func cancel() {
        close()
    }

    private func close() {
        guard !closed else { return }
        closed = true
        window.orderOut(nil)
        window.close()
        // Deferred: onClose may release the last strong reference to this controller,
        // and AppKit can still be dispatching an event to its window right now.
        DispatchQueue.main.async { self.onClose?() }
    }
}
