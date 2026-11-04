import Foundation

public struct SwitcherSelection: Equatable, Sendable {
    public private(set) var index: Int?
    public let count: Int

    public init(count: Int, reverse: Bool) {
        self.count = count
        index = count == 0 ? nil : count == 1 ? 0 : (reverse ? count - 1 : 1)
    }

    public mutating func next() {
        guard let i = index else { return }
        index = (i + 1) % count
    }

    public mutating func previous() {
        guard let i = index else { return }
        index = (i - 1 + count) % count
    }

    public mutating func select(_ i: Int) {
        guard i >= 0, i < count else { return }
        index = i
    }
}
