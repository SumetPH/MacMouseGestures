import CoreGraphics
import Foundation
import GestureCore

@MainActor
final class PrivateFluidGestureProbe {
  private let logger = EventLogger()
  private let poster = FluidGestureEventPoster()

  func run(direction: SyntheticSwipeDirection) async throws {
    let plan = fluidGesturePlan(direction: direction, changedFrameCount: 60)
    let point = CGEvent(source: nil)?.location ?? .zero
    logger.write(
      "fluid_synthesis_ready",
      [
        "direction": direction.fluidLogName,
        "event_count": "\(plan.count)",
        "starts_in_seconds": "2",
      ])
    try await Task.sleep(for: .seconds(2))

    for (index, step) in plan.enumerated() {
      guard let fields = poster.post(phase: step.phase, progress: step.progress, location: point)
      else {
        throw FluidSynthesisError.eventCreationFailed(index)
      }

      if index == 0 || index == 1 || index + 1 == plan.count {
        logger.write(
          "fluid_synthesis_posted",
          fields.merging([
            "index": "\(index)"
          ]) { current, _ in current })
      }

      if index + 1 < plan.count {
        let delay = step.phase == .mayBegin ? 1 : 8
        try await Task.sleep(for: .milliseconds(delay))
      }
    }
  }

}

extension SyntheticSwipeDirection {
  fileprivate var fluidLogName: String {
    switch self {
    case .left: "left"
    case .right: "right"
    }
  }
}

enum FluidSynthesisError: Error, CustomStringConvertible {
  case eventCreationFailed(Int)

  var description: String {
    switch self {
    case .eventCreationFailed(let index):
      "Could not create type-30 fluid gesture event at index \(index)"
    }
  }
}
