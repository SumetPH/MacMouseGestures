import CoreGraphics
import GestureCore

private let syntheticMarker: Int64 = 0x5350_4143_4553

enum InputPoster {
  static func rightClick(at point: CGPoint) {
    for type: CGEventType in [.rightMouseDown, .rightMouseUp] {
      let event = CGEvent(
        mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)
      event?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      event?.post(tap: .cghidEventTap)
    }
  }

  static func isSynthetic(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
  }
}
