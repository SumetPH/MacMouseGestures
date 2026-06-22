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

  static func missionControlShortcut(direction: GestureDirection) async {
    let source = CGEventSource(stateID: .privateState)
    let keyCode: CGKeyCode = (direction == .up) ? 126 : 125
    
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = .maskControl
    keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    keyDown?.post(tap: .cgSessionEventTap)
    
    try? await Task.sleep(for: .milliseconds(10))
    
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = []
    keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    keyUp?.post(tap: .cgSessionEventTap)
  }

  static func isSynthetic(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
  }

  static func postScrollEvent(
    dx: Int,
    dy: Int,
    dxLineInt: Int,
    dyLineInt: Int,
    dxLineFixed: Int64,
    dyLineFixed: Int64
  ) {
    guard let event = CGEvent(source: nil) else { return }
    
    event.setIntegerValueField(CGEventField(rawValue: 55)!, value: Int64(CGEventType.scrollWheel.rawValue))
    event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    
    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(dyLineInt))
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
    event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dyLineFixed)
    
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(dxLineInt))
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
    event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dxLineFixed)
    
    event.post(tap: .cgSessionEventTap)
  }
}
