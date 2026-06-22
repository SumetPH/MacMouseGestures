import Testing

@testable import GestureCore

@Suite("Recorded gesture replay timing")
struct ReplayScheduleTests {
  @Test("timestamps become offsets from the first event")
  func relativeOffsets() {
    #expect(replayOffsets(for: [100, 125, 175]) == [0, 25, 75])
  }

  @Test("an empty recording has no offsets")
  func emptyRecording() {
    #expect(replayOffsets(for: []) == [])
  }
}
