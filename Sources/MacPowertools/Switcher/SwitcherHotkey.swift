import AppKit
import CoreGraphics
import SwitcherCore

/// An active session event tap that feeds key, modifier, and mouse-down events to a
/// handler, and swallows the ones the handler doesn't pass through.
@MainActor
final class SwitcherHotkey {
    private let handler: (KeyInput, Modifiers) -> KeyAction
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    init(handler: @escaping (KeyInput, Modifiers) -> KeyAction) {
        self.handler = handler
    }

    isolated deinit {
        stop()
    }

    /// Installs the tap. Returns false if it couldn't be created (no permission).
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: switcherTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        tap = nil
        source = nil
    }

    /// Returns true to pass the event on, false to swallow it.
    fileprivate func handle(_ input: KeyInput, _ modifiers: Modifiers) -> Bool {
        switch handler(input, modifiers) {
        case .passThrough, .commit(passEvent: true):
            return true
        case .open, .moveNext, .movePrevious, .cancel, .swallow, .commit(passEvent: false):
            return false
        }
    }

    /// macOS disabled the tap (slow callback or user input): turn it back on, and
    /// re-check the modifiers so a release missed meanwhile still commits.
    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        // A closed switcher ignores this (the machine passes it through).
        _ = handler(.modifiersChanged, Self.modifiers(CGEventSource.flagsState(.combinedSessionState)))
    }

    nonisolated static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        Modifiers(option: flags.contains(SwitcherKeys.modifier),
                  shift: flags.contains(.maskShift),
                  command: flags.contains(.maskCommand),
                  control: flags.contains(.maskControl))
    }

    nonisolated static func input(_ type: CGEventType, _ event: CGEvent) -> KeyInput? {
        switch type {
        case .keyDown:
            // Autorepeat is treated like a press, so holding Tab keeps moving.
            switch CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)) {
            case SwitcherKeys.tab: return .tab(shift: event.flags.contains(.maskShift))
            case SwitcherKeys.escape: return .escape
            case SwitcherKeys.up: return .arrowUp
            case SwitcherKeys.down: return .arrowDown
            default: return .otherKey
            }
        case .flagsChanged: return .modifiersChanged
        case .leftMouseDown: return .mouseDown
        default: return nil
        }
    }
}

/// Event tap callback. The tap's run-loop source is on the main run loop, so this runs
/// on the main thread. `userInfo` is an unretained `SwitcherHotkey`, which removes the
/// tap before it goes away.
private func switcherTapCallback(_ proxy: CGEventTapProxy,
                                 _ type: CGEventType,
                                 _ event: CGEvent,
                                 _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let address = UInt(bitPattern: userInfo)
    func hotkey() -> SwitcherHotkey? {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return nil }
        return Unmanaged<SwitcherHotkey>.fromOpaque(pointer).takeUnretainedValue()
    }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { hotkey()?.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard let input = SwitcherHotkey.input(type, event) else { return Unmanaged.passUnretained(event) }
    let modifiers = SwitcherHotkey.modifiers(event.flags)
    let pass = MainActor.assumeIsolated { hotkey()?.handle(input, modifiers) ?? true }
    return pass ? Unmanaged.passUnretained(event) : nil
}
