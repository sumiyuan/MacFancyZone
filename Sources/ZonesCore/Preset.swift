import Foundation

public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var layout: LayoutNode
    public var spacing: Double
    public var outerGap: Bool

    public static let spacingRange: ClosedRange<Double> = 0...64

    public init(id: UUID, name: String, layout: LayoutNode, spacing: Double = 8, outerGap: Bool = true) {
        self.id = id
        self.name = name
        self.layout = layout
        self.spacing = spacing
        self.outerGap = outerGap
    }

    public func sanitized() -> Preset {
        var p = self
        p.layout = layout.sanitized()
        p.spacing = min(max(spacing, Self.spacingRange.lowerBound), Self.spacingRange.upperBound)
        return p
    }
}

public enum StarterPresets {
    public static let all: [Preset] = [
        Preset(id: UUID(uuidString: "5A1F0C2E-0001-4A6B-9C11-2C0105A0A001")!,
               name: "2 Columns",
               layout: .split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone)),
        Preset(id: UUID(uuidString: "5A1F0C2E-0002-4A6B-9C11-2C0105A0A002")!,
               name: "3 Columns",
               layout: .split(direction: .vertical, ratio: 1.0 / 3.0, first: .zone,
                              second: .split(direction: .vertical, ratio: 0.5, first: .zone, second: .zone))),
        Preset(id: UUID(uuidString: "5A1F0C2E-0003-4A6B-9C11-2C0105A0A003")!,
               name: "Wide Center",
               layout: .split(direction: .vertical, ratio: 0.25, first: .zone,
                              second: .split(direction: .vertical, ratio: 2.0 / 3.0, first: .zone, second: .zone))),
    ]
}
