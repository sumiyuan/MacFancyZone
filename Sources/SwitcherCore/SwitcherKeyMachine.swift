import Foundation

public enum KeyInput: Equatable, Sendable {
    case tab(shift: Bool)
    case escape, arrowUp, arrowDown
    case otherKey
    case modifiersChanged
    case mouseDown
}

public struct Modifiers: Equatable, Sendable {
    public var option, shift, command, control: Bool
    public init(option: Bool = false, shift: Bool = false, command: Bool = false, control: Bool = false) {
        self.option = option
        self.shift = shift
        self.command = command
        self.control = control
    }
}

public enum KeyAction: Equatable, Sendable {
    case passThrough
    case open(reverse: Bool)
    case moveNext, movePrevious
    case commit(passEvent: Bool)
    case cancel
    case swallow
}

public struct SwitcherKeyMachine: Sendable {
    public init() {}
    public private(set) var isOpen = false

    public mutating func handle(_ input: KeyInput, modifiers: Modifiers) -> KeyAction {
        guard isOpen else {
            if case .tab(let shift) = input, modifiers.option, !modifiers.command, !modifiers.control {
                isOpen = true
                return .open(reverse: shift)
            }
            return .passThrough
        }
        switch input {
        case .escape:
            isOpen = false
            return .cancel
        case .tab(let shift):
            return shift ? .movePrevious : .moveNext
        case .arrowDown:
            return .moveNext
        case .arrowUp:
            return .movePrevious
        case .modifiersChanged, .otherKey, .mouseDown:
            if !modifiers.option {
                isOpen = false
                return .commit(passEvent: true)
            }
            // Option still held: clicks reach the panel's rows; everything else is swallowed.
            return input == .mouseDown ? .passThrough : .swallow
        }
    }

    public mutating func reset() { isOpen = false }
}
