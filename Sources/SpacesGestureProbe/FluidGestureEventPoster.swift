import CoreGraphics
import GestureCore

final class FluidGestureEventPoster {
  private let source = CGEventSource(stateID: .privateState)

  func post(phase: FluidGesturePhase, progress: Double, location: CGPoint) -> [String: String]? {
    guard let event = makeEvent(phase: phase, progress: progress, location: location) else {
      return nil
    }
    event.post(tap: .cgSessionEventTap)
    return [
      "cg_type": "\(event.type.rawValue)",
      "data_bytes": event.data.map { "\(CFDataGetLength($0))" } ?? "none",
      "phase": "\(phase.rawFluidPhase)",
      "progress": "\(progress)",
    ]
  }

  private func makeEvent(
    phase: FluidGesturePhase,
    progress: Double,
    location: CGPoint
  ) -> CGEvent? {
    guard
      let type = CGEventType(rawValue: 30),
      let source,
      let event = CGEvent(source: source)
    else { return nil }

    event.type = type
    event.location = location
    event.flags = CGEventFlags(rawValue: phase == .changed ? 0x2000_0100 : 0x2000_0000)
    event.setIntegerValueField(field(0x6e), value: 0x17)
    event.setIntegerValueField(field(0x6f), value: 0)
    event.setIntegerValueField(field(0x70), value: 0)
    event.setIntegerValueField(field(0x84), value: phase.rawFluidPhase)
    event.setIntegerValueField(field(0x85), value: 0)
    event.setIntegerValueField(field(0x73), value: 0)
    event.setIntegerValueField(field(0x7b), value: 1)
    event.setIntegerValueField(field(0x86), value: 0)
    event.setDoubleValueField(field(0x7c), value: progress)
    event.setDoubleValueField(field(0x7d), value: 0)
    event.setDoubleValueField(field(0x7e), value: 0)
    event.setDoubleValueField(field(0x81), value: 0)
    event.setDoubleValueField(field(0x82), value: 0)
    event.setDoubleValueField(field(0x83), value: 0)
    event.setIntegerValueField(field(0x88), value: 0)
    event.setIntegerValueField(field(0x8a), value: 0)
    return event
  }

  private func field(_ rawValue: UInt32) -> CGEventField {
    // These private values were observed in BetterMouse's accepted type-30 stream.
    CGEventField(rawValue: rawValue)!
  }
}

extension FluidGesturePhase {
  var rawFluidPhase: Int64 {
    switch self {
    case .mayBegin: 0x80
    case .began: 1
    case .changed: 2
    case .ended: 4
    }
  }
}
