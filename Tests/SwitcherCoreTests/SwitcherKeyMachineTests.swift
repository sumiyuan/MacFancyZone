import Testing
@testable import SwitcherCore

private let opt = Modifiers(option: true)

private func openMachine() -> SwitcherKeyMachine {
    var m = SwitcherKeyMachine()
    _ = m.handle(.tab(shift: false), modifiers: opt)
    return m
}

@Test func optionTabOpensAndIsSwallowed() {
    var m = SwitcherKeyMachine()
    #expect(m.handle(.tab(shift: false), modifiers: opt) == .open(reverse: false))
    #expect(m.isOpen)
}
@Test func optionShiftTabOpensReversed() {
    var m = SwitcherKeyMachine()
    #expect(m.handle(.tab(shift: true), modifiers: Modifiers(option: true, shift: true)) == .open(reverse: true))
    #expect(m.isOpen)
}
@Test func plainTabPassesThrough() {
    var m = SwitcherKeyMachine()
    #expect(m.handle(.tab(shift: false), modifiers: Modifiers()) == .passThrough)
    #expect(!m.isOpen)
}
@Test func optionLetterPassesThroughWhenClosed() {
    var m = SwitcherKeyMachine()
    #expect(m.handle(.otherKey, modifiers: opt) == .passThrough)
    #expect(!m.isOpen)
}
@Test func optionTabWithCommandOrControlPassesThrough() {
    var m = SwitcherKeyMachine()
    #expect(m.handle(.tab(shift: false), modifiers: Modifiers(option: true, command: true)) == .passThrough)
    #expect(!m.isOpen)
    #expect(m.handle(.tab(shift: false), modifiers: Modifiers(option: true, control: true)) == .passThrough)
    #expect(!m.isOpen)
}
@Test func tabAndShiftTabMoveWhileOpen() {
    var m = openMachine()
    #expect(m.handle(.tab(shift: false), modifiers: opt) == .moveNext)
    #expect(m.handle(.tab(shift: true), modifiers: opt) == .movePrevious)
    #expect(m.isOpen)
}
@Test func arrowsMoveWhileOpen() {
    var m = openMachine()
    #expect(m.handle(.arrowDown, modifiers: opt) == .moveNext)
    #expect(m.handle(.arrowUp, modifiers: opt) == .movePrevious)
}
@Test func escapeCancelsAndCloses() {
    var m = openMachine()
    #expect(m.handle(.escape, modifiers: opt) == .cancel)
    #expect(!m.isOpen)
}
@Test func releasingOptionCommits() {
    var m = openMachine()
    #expect(m.handle(.modifiersChanged, modifiers: Modifiers()) == .commit(passEvent: true))
    #expect(!m.isOpen)
}
@Test func otherKeysAreSwallowedWhileOpen() {
    var m = openMachine()
    #expect(m.handle(.otherKey, modifiers: opt) == .swallow)
    #expect(m.handle(.modifiersChanged, modifiers: Modifiers(option: true, shift: true)) == .swallow)
    #expect(m.isOpen)
}
@Test func eventWithoutOptionWhileOpenCommits() {
    var m = openMachine()
    #expect(m.handle(.otherKey, modifiers: Modifiers()) == .commit(passEvent: true))
    #expect(!m.isOpen)
    m = openMachine()
    #expect(m.handle(.mouseDown, modifiers: Modifiers()) == .commit(passEvent: true))
    #expect(!m.isOpen)
}
@Test func mouseDownWithOptionWhileOpenPassesThrough() {
    var m = openMachine()
    #expect(m.handle(.mouseDown, modifiers: opt) == .passThrough)
    #expect(m.isOpen)
}
@Test func resetCloses() {
    var m = openMachine()
    m.reset()
    #expect(!m.isOpen)
}
@Test func tabWithoutOptionWhileOpenCommits() {
    // A missed Option release must not trap Tab or the arrows in the switcher.
    for input in [KeyInput.tab(shift: false), .tab(shift: true), .arrowDown, .arrowUp] {
        var m = openMachine()
        #expect(m.handle(input, modifiers: Modifiers()) == .commit(passEvent: true))
        #expect(!m.isOpen)
    }
    var m = openMachine()
    #expect(m.handle(.tab(shift: true), modifiers: Modifiers(shift: true)) == .commit(passEvent: true))
    #expect(!m.isOpen)
}
@Test func escapeWithoutOptionWhileOpenCancels() {
    var m = openMachine()
    #expect(m.handle(.escape, modifiers: Modifiers()) == .cancel)
    #expect(!m.isOpen)
}
