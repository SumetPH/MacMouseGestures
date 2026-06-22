import AppKit
import CoreGraphics
import GestureCore

@MainActor
final class NativeGestureRecorder {
  private let logger: EventLogger
  private var sequence = 0
  private var seenSequence = 0

  init(logger: EventLogger) {
    self.logger = logger
  }

  static func shouldRecord(type: CGEventType) -> Bool {
    capturePolicy(forEventType: type.rawValue) != .envelopeOnly
  }

  func recordEnvelope(type: CGEventType, event: CGEvent) {
    guard seenSequence < 2_000 else { return }
    seenSequence += 1
    logger.write(
      "native_event_seen",
      [
        "sequence": "\(seenSequence)",
        "cg_type": "\(type.rawValue)",
        "cg_flags": "\(event.flags.rawValue)",
      ])
  }

  func record(type: CGEventType, event: CGEvent) {
    sequence += 1
    var rawFields: [String: String] = [
      "sequence": "\(sequence)",
      "cg_type": "\(type.rawValue)",
      "cg_flags": "\(event.flags.rawValue)",
      "cg_timestamp": "\(event.timestamp)",
      "mouse_x": "\(event.location.x)",
      "mouse_y": "\(event.location.y)",
    ]

    if let data = event.data {
      rawFields["cg_data_base64"] = (data as Data).base64EncodedString()
      rawFields["cg_data_bytes"] = "\(CFDataGetLength(data))"
    }
    logger.write("native_gesture_raw", rawFields)

    var fields = rawFields
    if capturePolicy(forEventType: type.rawValue) == .coreGraphicsScrollFields {
      fields.merge(scrollWheelFields(event)) { current, _ in current }
    }
    fields.merge(pointerDisplayFields()) { current, _ in current }
    logger.write("native_gesture_event", fields)
  }

  private func scrollWheelFields(_ event: CGEvent) -> [String: String] {
    [
      "axis_1": "\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))",
      "axis_2": "\(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))",
      "point_axis_1": "\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))",
      "point_axis_2": "\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))",
      "continuous": "\(event.getIntegerValueField(.scrollWheelEventIsContinuous))",
      "scroll_phase": "\(event.getIntegerValueField(.scrollWheelEventScrollPhase))",
      "momentum_phase": "\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))",
      "scroll_count": "\(event.getIntegerValueField(.scrollWheelEventScrollCount))",
    ]
  }

  private func pointerDisplayFields() -> [String: String] {
    let pointer = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
    else {
      return ["display_id": "unknown"]
    }
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    let displayID = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    return [
      "display_id": displayID.map(String.init) ?? "unknown",
      "display_frame": NSStringFromRect(screen.frame),
    ]
  }
}
