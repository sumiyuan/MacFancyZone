import SwiftUI
import ZonesCore

/// A 16:10 thumbnail of a preset's zones, drawn with the same geometry the snapper uses.
struct LayoutPreview: View {
    let preset: Preset
    let isActive: Bool

    init(preset: Preset, isActive: Bool) {
        self.preset = preset
        self.isActive = isActive
    }

    private static let cornerRadius: CGFloat = 7
    private static let borderWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let scaled = preset.spacing * Double(size.width) / 1440
            let spacing = preset.spacing > 0 ? max(scaled, 1.5) : 0
            let zones = ZoneGeometry.zoneRects(for: preset.layout, in: rect, spacing: spacing, outerGap: preset.outerGap)
            let fill = isActive ? Color(nsColor: .systemBlue).opacity(0.65) : Color.white.opacity(0.28)
            for zone in zones {
                context.fill(Path(roundedRect: zone, cornerRadius: 2), with: .color(fill))
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(Color(nsColor: .systemBlue), lineWidth: Self.borderWidth)
            }
        }
    }
}
