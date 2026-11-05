import SwiftUI
import ZonesCore

struct MenuPanelView: View {
    let model: PanelModel

    init(model: PanelModel) { self.model = model }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let linkColor = Color(red: 0.56, green: 0.72, blue: 1.0)

    var body: some View {
        VStack(spacing: 8) {
            if model.permissionNeeded { permissionBanner }
            layoutsCard
            toggleRow
            // Future cards (e.g. the volume mixer) go here: just add another view to this stack.
            footer
        }
        .padding(10)
        .frame(width: 332)
        .preferredColorScheme(.dark)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(linkColor)
        }
        .buttonStyle(.plain)
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Accessibility permission needed")
            Spacer(minLength: 0)
            linkButton("Open Settings", action: model.onOpenPermissionSettings)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.54))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private var layoutsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Layouts").font(.system(size: 13, weight: .semibold))
                Spacer()
                linkButton("All layouts…", action: model.onAllLayouts)
            }
            if model.monitors.count > 1 {
                Picker("Monitor", selection: Binding(
                    get: { model.selectedMonitorID ?? model.monitors.first?.id ?? "" },
                    set: { model.onSelectMonitor($0) })
                ) {
                    ForEach(model.monitors, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.tiles) { preset in
                    Button { model.onApplyTile(preset.id) } label: {
                        VStack(spacing: 4) {
                            LayoutPreview(preset: preset, isActive: preset.id == model.activePresetID)
                            Text(preset.name)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.87))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset.id == model.activePresetID ? .isSelected : [])
                }
            }
            HStack {
                linkButton("＋ New layout", action: model.onNewLayout)
                Spacer()
                linkButton("Edit current…", action: model.onEditCurrent)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var toggleRow: some View {
        HStack(spacing: 8) {
            toggleButton(symbol: "rectangle.on.rectangle", title: "Window Switcher",
                         subtitle: model.switcherOn ? "On · ⌥ Tab" : "Off",
                         isOn: model.switcherOn, action: model.onToggleSwitcher)
            toggleButton(symbol: "power", title: "Launch at Login",
                         subtitle: launchSubtitle,
                         isOn: model.launch == .on, action: model.onToggleLaunch)
        }
    }

    private var launchSubtitle: String {
        switch model.launch {
        case .on: "On"
        case .off: "Off"
        case .needsApproval: "Needs approval"
        }
    }

    private func toggleButton(symbol: String, title: String, subtitle: String,
                              isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isOn ? Color(nsColor: .systemBlue) : Color.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12)).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Color(white: 0.67)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: model.onQuit) {
                Text("Quit MacPowertools").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}
