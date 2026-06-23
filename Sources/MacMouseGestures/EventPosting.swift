import CoreGraphics
import GestureCore
import Foundation

@_silgen_name("CoreDockSendNotification")
private func CoreDockSendNotification(_ name: CFString, _ unknown: Int)

private let syntheticMarker: Int64 = 0x5350_4143_4553
private let defaultPixelsPerLine = 10.0

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
    let notificationName: String
    if direction == .up {
      notificationName = "com.apple.expose.awake"
    } else {
      notificationName = "com.apple.expose.front.awake"
    }
    
    print("[DEBUG] missionControlShortcut called, direction: \(direction), sending notification: \(notificationName)")
    fflush(stdout)
    
    CoreDockSendNotification(notificationName as CFString, 0)
  }

  static func switchSpaceShortcut(direction: GestureDirection) async {
    let keyCode: CGKeyCode = (direction == .left) ? 124 : 123
    
    print("[DEBUG] switchSpaceShortcut called, direction: \(direction), keyCode: \(keyCode)")
    fflush(stdout)
    
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = .maskControl
    keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = []
    keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    
    print("[DEBUG] posting keyDown to cgSessionEventTap")
    fflush(stdout)
    keyDown?.post(tap: .cgSessionEventTap)
    
    try? await Task.sleep(for: .milliseconds(15))
    
    print("[DEBUG] posting keyUp to cgSessionEventTap")
    fflush(stdout)
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
    dyLineFixed: Int64,
    mode: ScrollEventPostingMode
  ) {
    switch mode {
    case .fieldValues:
      postFieldValueScrollEvent(
        dx: dx,
        dy: dy,
        dxLineInt: dxLineInt,
        dyLineInt: dyLineInt,
        dxLineFixed: dxLineFixed,
        dyLineFixed: dyLineFixed
      )
    case .eventSourcePixels:
      postEventSourcePixelScrollEvent(dx: dx, dy: dy)
    }
  }

  private static func postFieldValueScrollEvent(
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

  private static func postEventSourcePixelScrollEvent(dx: Int, dy: Int) {
    let source = CGEventSource(stateID: .privateState)
    source?.pixelsPerLine = defaultPixelsPerLine
    guard let event = CGEvent(
      scrollWheelEvent2Source: source,
      units: .pixel,
      wheelCount: 2,
      wheel1: Int32(dy),
      wheel2: Int32(dx),
      wheel3: 0
    ) else { return }

    event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.post(tap: .cgSessionEventTap)
  }
}
