import Testing

@testable import GestureCore

@Suite("Spaces shortcut event sequence")
struct ShortcutSequenceTests {
  @Test("right sends a Control-Right key-down and key-up pair")
  func controlRightChord() {
    #expect(
      spacesShortcutSequence(for: .right) == [
        KeyStroke(keyCode: 124, isDown: true, controlActive: true),
        KeyStroke(keyCode: 124, isDown: false, controlActive: true),
      ])
  }

  @Test("left uses the left-arrow key code")
  func controlLeftChord() {
    let sequence = spacesShortcutSequence(for: .left)

    #expect(sequence[0].keyCode == 123)
    #expect(sequence[1].keyCode == 123)
  }
}
