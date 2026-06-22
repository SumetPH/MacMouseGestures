public enum SyntheticSwipeDirection: Equatable, Sendable {
  case left
  case right
}

public enum SyntheticGesturePhase: Equatable, Sendable {
  case began
  case ended
}

public struct SyntheticSwipeStep: Equatable, Sendable {
  public let phase: SyntheticGesturePhase
  public let direction: SyntheticSwipeDirection?

  public init(phase: SyntheticGesturePhase, direction: SyntheticSwipeDirection?) {
    self.phase = phase
    self.direction = direction
  }
}

public func touchSynthesisPlan(direction: SyntheticSwipeDirection) -> [SyntheticSwipeStep] {
  [
    SyntheticSwipeStep(phase: .began, direction: nil),
    SyntheticSwipeStep(phase: .ended, direction: direction),
  ]
}
