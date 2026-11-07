import SwiftUI

/// The Volume Mixer card: one row per app making sound, with mute and a 0–150% slider.
struct MixerCard: View {
    let model: MixerModel

    private let linkColor = Color(red: 0.56, green: 0.72, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume Mixer").font(.system(size: 13, weight: .semibold))
            if model.permissionNeeded { permissionBanner }
            if model.rows.isEmpty {
                Text("Nothing is playing")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.6))
            } else {
                ForEach(model.rows) { row in rowView(row) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Allow System Audio Recording")
            Spacer(minLength: 0)
            Button(action: model.onOpenAudioSettings) {
                Text("Open Settings").font(.system(size: 12)).foregroundStyle(linkColor)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.54))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowView(_ row: MixerRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(row.name).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if row.unavailable {
                    Text("Can't adjust this app").font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
                }
            }
            HStack(spacing: 8) {
                Button { model.onToggleMute(row.id) } label: {
                    Image(systemName: row.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .frame(width: 18)
                        .foregroundStyle(row.muted ? Color(white: 0.6) : .white)
                }
                .buttonStyle(.plain)
                .disabled(row.unavailable)
                .help(row.muted ? "Unmute" : "Mute")
                Slider(value: Binding(
                    get: { row.volume },
                    set: { v in model.onSetVolume(row.id, abs(v - 1.0) <= 0.03 ? 1.0 : v) }
                ), in: 0...1.5)
                .controlSize(.small)
                .overlay { notch }
                .opacity(row.muted ? 0.5 : 1)
                .disabled(row.unavailable)
                Text("\(Int((row.volume * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(white: 0.75))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    /// A small mark at 100% (two thirds of the 0–150% track).
    private var notch: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 1, height: 8)
                .position(x: geo.size.width * 2 / 3, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}
