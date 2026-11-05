import AppKit
import Observation
import SwiftUI
import ZonesCore

/// Data and action hooks for the All Layouts window. `AppController` applies changes and pushes
/// the new `presets` / `favourites` back in; this model never mutates `ZonesState`.
@MainActor @Observable
final class AllLayoutsModel {
    var presets: [Preset] = []
    var favourites: [UUID] = []
    /// Open in the editor: rename and delete are disabled.
    var lockedPresetID: UUID?

    var onToggleFavourite: (UUID) -> Void = { _ in }
    var onRename: (UUID, String) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    var onRestoreStarters: () -> Void = {}
}

@MainActor
final class AllLayoutsWindowController {
    private let model: AllLayoutsModel
    private let rename = RenameState()
    private var window: NSWindow?

    init(model: AllLayoutsModel) {
        self.model = model
    }

    func show() {
        rename.renamingID = nil
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "All Layouts"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: AllLayoutsView(model: model, rename: rename))
            w.setContentSize(NSSize(width: 420, height: 520))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Inline-rename state. Held in an observable object because the `@State` macro plugin
/// isn't available in the Command Line Tools toolchain.
@MainActor @Observable
private final class RenameState {
    var renamingID: UUID?
    var draft = ""

    /// Ends the rename in progress, saving the draft (Finder-style). Reverts instead if the
    /// draft is blank or unchanged, or the layout is locked by the editor.
    func commit(in model: AllLayoutsModel) {
        guard let id = renamingID else { return }
        renamingID = nil
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.lockedPresetID != id, !trimmed.isEmpty,
              let preset = model.presets.first(where: { $0.id == id }),
              trimmed != preset.name else { return }
        model.onRename(id, trimmed)
    }
}

private struct AllLayoutsView: View {
    let model: AllLayoutsModel
    let rename: RenameState

    var body: some View {
        VStack(spacing: 0) {
            List(model.presets) { preset in
                AllLayoutsRow(preset: preset, model: model, rename: rename)
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Restore Starter Presets") { model.onRestoreStarters() }
                Spacer()
                if model.favourites.count >= ZonesState.maxFavourites {
                    Text("Up to \(ZonesState.maxFavourites) favourites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .onChange(of: model.presets.map(\.id)) { _, ids in
            if let id = rename.renamingID, !ids.contains(id) { rename.renamingID = nil }
        }
    }
}

private struct AllLayoutsRow: View {
    let preset: Preset
    let model: AllLayoutsModel
    let rename: RenameState

    @FocusState private var fieldFocused: Bool

    private var isFavourite: Bool { model.favourites.contains(preset.id) }
    private var starDisabled: Bool { !isFavourite && model.favourites.count >= ZonesState.maxFavourites }
    private var isRenaming: Bool { rename.renamingID == preset.id }
    private var isLocked: Bool { model.lockedPresetID == preset.id }

    var body: some View {
        HStack(spacing: 10) {
            LayoutPreview(preset: preset, isActive: false)
                .frame(width: 96)
            if isRenaming {
                @Bindable var rename = rename
                TextField("Name", text: $rename.draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { rename.commit(in: model) }
                    .onExitCommand { rename.renamingID = nil }   // Esc cancels
                    .onAppear { fieldFocused = true }
                    .onChange(of: fieldFocused) { _, focused in
                        // Losing focus saves the draft, like Finder.
                        if !focused && isRenaming { rename.commit(in: model) }
                    }
                    .onChange(of: isLocked) { _, locked in
                        if locked { rename.renamingID = nil }
                    }
            } else {
                Text(preset.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Button {
                model.onToggleFavourite(preset.id)
            } label: {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .foregroundStyle(isFavourite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(starDisabled)
            .help(starDisabled ? "Up to \(ZonesState.maxFavourites) favourites" : (isFavourite ? "Remove from favourites" : "Add to favourites"))

            Button {
                rename.commit(in: model)   // finish any other row's rename first
                rename.draft = preset.name
                rename.renamingID = preset.id
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .disabled(isLocked)
            .help("Rename")

            Button {
                model.onDelete(preset.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isLocked || model.presets.count <= 1)
            .help("Delete")
        }
        .padding(.vertical, 4)
    }
}
