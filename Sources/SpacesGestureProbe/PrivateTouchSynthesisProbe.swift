import CTouchEvents
import CoreGraphics
import Foundation
import GestureCore

@MainActor
final class PrivateTouchSynthesisProbe {
  private let logger = EventLogger()

  func run(direction: SyntheticSwipeDirection) async throws {
    let plan = touchSynthesisPlan(direction: direction)
    logger.write(
      "touch_synthesis_ready",
      [
        "direction": direction.logName,
        "event_count": "\(plan.count)",
        "starts_in_seconds": "2",
      ])
    try await Task.sleep(for: .seconds(2))

    for (index, step) in plan.enumerated() {
      guard let event = makeEvent(for: step) else {
        throw TouchSynthesisError.eventCreationFailed(index)
      }
      event.post(tap: .cgSessionEventTap)
      logger.write(
        "touch_synthesis_posted",
        [
          "cg_type": "\(event.type.rawValue)",
          "direction": step.direction?.logName ?? "none",
          "index": "\(index)",
          "phase": step.phase.logName,
        ])

      if index + 1 < plan.count {
        try await Task.sleep(for: .milliseconds(150))
      }
    }
  }

  private func makeEvent(for step: SyntheticSwipeStep) -> CGEvent? {
    let info = NSMutableDictionary()
    info[kTLInfoKeyGestureSubtype as String] = NSNumber(value: 0x10)
    info[kTLInfoKeyGesturePhase as String] = NSNumber(value: step.phase.rawPhase)
    if let direction = step.direction {
      info[kTLInfoKeySwipeDirection as String] = NSNumber(value: direction.rawDirection)
    }

    return tl_CGEventCreateFromGesture(info, [] as CFArray)?.takeRetainedValue()
  }
}

extension SyntheticGesturePhase {
  fileprivate var rawPhase: Int32 {
    switch self {
    case .began: 1
    case .ended: 4
    }
  }

  fileprivate var logName: String {
    switch self {
    case .began: "began"
    case .ended: "ended"
    }
  }
}

extension SyntheticSwipeDirection {
  fileprivate var rawDirection: Int32 {
    switch self {
    case .left: 4
    case .right: 8
    }
  }

  fileprivate var logName: String {
    switch self {
    case .left: "left"
    case .right: "right"
    }
  }
}

enum TouchSynthesisError: Error, CustomStringConvertible {
  case eventCreationFailed(Int)

  var description: String {
    switch self {
    case .eventCreationFailed(let index):
      "TouchEvents could not create gesture event at index \(index)"
    }
  }
}
