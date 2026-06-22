import Testing

@testable import GestureCore

@Suite("Touch synthesis plan")
struct TouchSynthesisPlanTests {
  @Test("left swipe begins without direction and ends with left direction")
  func leftSwipeSequence() {
    #expect(
      touchSynthesisPlan(direction: .left) == [
        .init(phase: .began, direction: nil),
        .init(phase: .ended, direction: .left),
      ])
  }

  @Test("right swipe begins without direction and ends with right direction")
  func rightSwipeSequence() {
    #expect(
      touchSynthesisPlan(direction: .right) == [
        .init(phase: .began, direction: nil),
        .init(phase: .ended, direction: .right),
      ])
  }
}
