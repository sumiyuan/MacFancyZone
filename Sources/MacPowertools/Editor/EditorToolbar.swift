import SwiftUI
import ZonesCore

/// The preset being edited. Shared by the toolbar (SwiftUI) and the canvas (AppKit).
@MainActor
final class EditorDraft: ObservableObject {
    let id: UUID
    @Published var name: String
    @Published var layout: LayoutNode { didSet { onChange?() } }
    @Published var spacing: Double { didSet { onChange?() } }
    @Published var outerGap: Bool { didSet { onChange?() } }

    /// Called after anything that affects the canvas drawing changes.
    var onChange: (() -> Void)?

    init(_ preset: Preset) {
        id = preset.id
        name = preset.name
        layout = preset.layout
        spacing = preset.spacing
        outerGap = preset.outerGap
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var preset: Preset {
        Preset(id: id, name: trimmedName, layout: layout, spacing: spacing, outerGap: outerGap)
    }
}

struct EditorToolbar: View {
    @ObservedObject var draft: EditorDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Stepper(value: $draft.spacing, in: Preset.spacingRange, step: 1) {
                Text("Spacing: \(Int(draft.spacing)) pt")
                    .monospacedDigit()
                    .frame(minWidth: 96, alignment: .leading)
            }
            Toggle("Outer gap", isOn: $draft.outerGap)
            Divider().frame(height: 18)
            Button("Reset") { draft.layout = .zone }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmedName.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
