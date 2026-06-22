import CoreGraphics
import GestureCore

private let syntheticMarker: Int64 = 0x5350_4143_4553

final class ScrollEventPoster {
  private let source = CGEventSource(stateID: .hidSystemState)
  private let scale: Double
  private var count: Int64 = 0

  init(scale: Double) { self.scale = scale }

  func beginSequence() { count = 0 }

  func post(deltaX: Double, phase: CGScrollPhase) -> [String: String]? {
    let horizontalPixels = Int32(clamping: Int64((-deltaX * scale).rounded()))
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .pixel,
        wheelCount: 2,
        wheel1: 0,
        wheel2: horizontalPixels,
        wheel3: 0
      )
    else { return nil }

    count += 1
    event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventScrollCount, value: count)
    event.post(tap: .cghidEventTap)

    return [
      "horizontal_pixels": "\(horizontalPixels)",
      "is_continuous": "\(event.getIntegerValueField(.scrollWheelEventIsContinuous))",
      "scroll_phase": "\(event.getIntegerValueField(.scrollWheelEventScrollPhase))",
      "momentum_phase": "\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))",
      "scroll_count": "\(count)",
    ]
  }
}

enum InputPoster {
  static func shortcut(direction: GestureDirection) async {
    let source = CGEventSource(stateID: .privateState)
    for stroke in spacesShortcutSequence(for: direction) {
      let event = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(stroke.keyCode),
        keyDown: stroke.isDown
      )
      event?.flags = stroke.controlActive ? .maskControl : []
      event?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      event?.post(tap: .cgSessionEventTap)
      if stroke.isDown {
        try? await Task.sleep(for: .milliseconds(200))
      }
    }
  }

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
