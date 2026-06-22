public struct KeyStroke: Equatable, Sendable {
  public let keyCode: UInt16
  public let isDown: Bool
  public let controlActive: Bool

  public init(keyCode: UInt16, isDown: Bool, controlActive: Bool) {
    self.keyCode = keyCode
    self.isDown = isDown
    self.controlActive = controlActive
  }
}

public func spacesShortcutSequence(for direction: GestureDirection) -> [KeyStroke] {
  let arrowKey: UInt16 = direction == .left ? 123 : 124
  return [
    KeyStroke(keyCode: arrowKey, isDown: true, controlActive: true),
    KeyStroke(keyCode: arrowKey, isDown: false, controlActive: true),
  ]
}
