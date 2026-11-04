import CoreGraphics
import Foundation

public enum SplitDirection: String, Codable, Sendable { case vertical, horizontal } // vertical = side by side (splits x)
public enum Branch: Int, Codable, Sendable { case first, second }
public typealias NodePath = [Branch]

public struct Zone: Equatable, Sendable {
    public let number: Int
    public let path: NodePath
    public let unitRect: CGRect

    public init(number: Int, path: NodePath, unitRect: CGRect) {
        self.number = number
        self.path = path
        self.unitRect = unitRect
    }
}

public struct Divider: Equatable, Sendable {
    public let path: NodePath
    public let direction: SplitDirection
    public let position: Double
    public let start: Double
    public let span: Double
    public let crossStart: Double
    public let crossSpan: Double

    public init(path: NodePath, direction: SplitDirection, position: Double,
                start: Double, span: Double, crossStart: Double, crossSpan: Double) {
        self.path = path
        self.direction = direction
        self.position = position
        self.start = start
        self.span = span
        self.crossStart = crossStart
        self.crossSpan = crossSpan
    }
}

public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case zone
    case split(direction: SplitDirection, ratio: Double, first: LayoutNode, second: LayoutNode)

    public static let ratioRange: ClosedRange<Double> = 0.05...0.95

    private static func clamp(_ r: Double) -> Double {
        min(max(r, ratioRange.lowerBound), ratioRange.upperBound)
    }

    private static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Splits a rect at `ratio` along `direction`.
    private static func children(of rect: CGRect, _ direction: SplitDirection, _ ratio: Double) -> (CGRect, CGRect) {
        switch direction {
        case .vertical:
            let w = rect.width * ratio
            return (CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                    CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
        case .horizontal:
            let h = rect.height * ratio
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                    CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
        }
    }

    // MARK: Queries

    public func zones() -> [Zone] {
        var result: [Zone] = []
        collectZones(path: [], rect: Self.unit, into: &result)
        return result
    }

    private func collectZones(path: NodePath, rect: CGRect, into out: inout [Zone]) {
        switch self {
        case .zone:
            out.append(Zone(number: out.count + 1, path: path, unitRect: rect))
        case let .split(direction, ratio, first, second):
            let (a, b) = Self.children(of: rect, direction, ratio)
            first.collectZones(path: path + [.first], rect: a, into: &out)
            second.collectZones(path: path + [.second], rect: b, into: &out)
        }
    }

    public func dividers() -> [Divider] {
        var result: [Divider] = []
        collectDividers(path: [], rect: Self.unit, into: &result)
        return result
    }

    private func collectDividers(path: NodePath, rect: CGRect, into out: inout [Divider]) {
        guard case let .split(direction, ratio, first, second) = self else { return }
        let (a, b) = Self.children(of: rect, direction, ratio)
        switch direction {
        case .vertical:
            out.append(Divider(path: path, direction: direction, position: a.maxX,
                               start: rect.minX, span: rect.width,
                               crossStart: rect.minY, crossSpan: rect.height))
        case .horizontal:
            out.append(Divider(path: path, direction: direction, position: a.maxY,
                               start: rect.minY, span: rect.height,
                               crossStart: rect.minX, crossSpan: rect.width))
        }
        first.collectDividers(path: path + [.first], rect: a, into: &out)
        second.collectDividers(path: path + [.second], rect: b, into: &out)
    }

    // MARK: Edits

    /// Replaces the node at `path` using `transform`; nil if the path is invalid or the transform fails.
    private func replacing(at path: ArraySlice<Branch>, _ transform: (LayoutNode) -> LayoutNode?) -> LayoutNode? {
        guard let head = path.first else { return transform(self) }
        guard case let .split(direction, ratio, first, second) = self else { return nil }
        let rest = path.dropFirst()
        switch head {
        case .first:
            return first.replacing(at: rest, transform).map { .split(direction: direction, ratio: ratio, first: $0, second: second) }
        case .second:
            return second.replacing(at: rest, transform).map { .split(direction: direction, ratio: ratio, first: first, second: $0) }
        }
    }

    public func splitting(zoneAt path: NodePath, direction: SplitDirection, ratio: Double) -> LayoutNode? {
        guard Self.ratioRange.contains(ratio) else { return nil }
        return replacing(at: path[...]) { node in
            guard case .zone = node else { return nil }
            return .split(direction: direction, ratio: ratio, first: .zone, second: .zone)
        }
    }

    public func resizing(splitAt path: NodePath, ratio: Double) -> LayoutNode? {
        replacing(at: path[...]) { node in
            guard case let .split(direction, _, first, second) = node else { return nil }
            return .split(direction: direction, ratio: Self.clamp(ratio), first: first, second: second)
        }
    }

    public func removingDivider(at path: NodePath) -> LayoutNode? {
        replacing(at: path[...]) { node in
            guard case .split(_, _, .zone, .zone) = node else { return nil }
            return .zone
        }
    }

    public func sanitized() -> LayoutNode {
        switch self {
        case .zone:
            return .zone
        case let .split(direction, ratio, first, second):
            return .split(direction: direction, ratio: Self.clamp(ratio),
                          first: first.sanitized(), second: second.sanitized())
        }
    }
}
