import Testing
@testable import SwitcherCore

@Test func selectionStartsOnSecondRow() { #expect(SwitcherSelection(count: 4, reverse: false).index == 1) }
@Test func reverseSelectionStartsOnLastRow() { #expect(SwitcherSelection(count: 4, reverse: true).index == 3) }
@Test func selectionWithOneWindowStartsAtZero() { #expect(SwitcherSelection(count: 1, reverse: false).index == 0) }
@Test func selectionWithZeroWindowsIsEmpty() { #expect(SwitcherSelection(count: 0, reverse: false).index == nil) }
@Test func nextAndPreviousWrap() {
    var s = SwitcherSelection(count: 3, reverse: true)
    #expect(s.index == 2)
    s.next()
    #expect(s.index == 0)
    s.previous()
    #expect(s.index == 2)
}
@Test func selectOutOfRangeIsIgnored() {
    var s = SwitcherSelection(count: 3, reverse: false)
    s.select(5); #expect(s.index == 1)
    s.select(-1); #expect(s.index == 1)
    s.select(2); #expect(s.index == 2)
}
@Test func emptySelectionIgnoresMoves() {
    var s = SwitcherSelection(count: 0, reverse: false)
    s.next(); s.previous()
    #expect(s.index == nil)
}
