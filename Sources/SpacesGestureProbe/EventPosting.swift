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
}
