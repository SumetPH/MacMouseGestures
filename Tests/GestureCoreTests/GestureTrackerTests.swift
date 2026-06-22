import CoreGraphics
import Testing

@testable import GestureCore

@Suite("Right-drag gesture tracking")
struct GestureTrackerTests {
  @Test("a short drag remains a normal right click")
  func shortDragIsClick() {
    var tracker = GestureTracker(threshold: 80)
    tracker.begin(at: CGPoint(x: 100, y: 100))
    _ = tracker.move(to: CGPoint(x: 140, y: 105))

    #expect(tracker.end() == .rightClick)
  }

  @Test("a horizontal drag reports progress and direction")
  func horizontalDrag() {
    var tracker = GestureTracker(threshold: 80)
    tracker.begin(at: CGPoint(x: 100, y: 100))

    let update = tracker.move(to: CGPoint(x: 20, y: 110))

    #expect(update?.deltaX == -80)
    #expect(update?.progress == 1)
    #expect(update?.direction == .left)
    #expect(tracker.end() == .switchSpace(.left))
  }

  @Test("vertical movement does not become a Spaces gesture")
  func verticalDragIsRejected() {
    var tracker = GestureTracker(threshold: 80)
    tracker.begin(at: CGPoint(x: 100, y: 100))
    let update = tracker.move(to: CGPoint(x: 130, y: 220))

    #expect(update == nil)
    #expect(tracker.end() == .rightClick)
  }

  @Test("mouse-up position is the final sample for a fast flick")
  func fastFlickUsesReleasePosition() {
    var tracker = GestureTracker(threshold: 180)
    tracker.begin(at: CGPoint(x: 500, y: 100))
    _ = tracker.move(to: CGPoint(x: 420, y: 100))

    let completion = tracker.end(at: CGPoint(x: 250, y: 100))

    #expect(completion.update?.deltaX == -250)
    #expect(completion.outcome == .switchSpace(.left))
  }

  @Test("ending resets the tracker")
  func endResetsState() {
    var tracker = GestureTracker(threshold: 80)
    #expect(tracker.isTracking == false)
    tracker.begin(at: .zero)
    #expect(tracker.isTracking == true)
    _ = tracker.move(to: CGPoint(x: 100, y: 0))
    _ = tracker.end()

    #expect(tracker.isTracking == false)
    #expect(tracker.end() == .none)
  }
}
