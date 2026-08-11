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

  static func performMissionControlAction(direction: GestureDirection) {
    performMouseButtonAction(direction == .up ? .missionControl : .applicationWindows)
  }

  static func switchSpaceShortcut(direction: GestureDirection) async {
    let keyCode: CGKeyCode = (direction == .left) ? 124 : 123
    
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = .maskControl
    keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = []
    keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
    
    keyDown?.post(tap: .cgSessionEventTap)
    
    try? await Task.sleep(for: .milliseconds(15))
    
    keyUp?.post(tap: .cgSessionEventTap)
  }

  static func performMouseButtonAction(_ action: MouseButtonAction) {
    let notificationName: String
    switch action {
    case .none:
      return
    case .missionControl:
      notificationName = "com.apple.expose.awake"
    case .applicationWindows:
      notificationName = "com.apple.expose.front.awake"
    }
    CoreDockSendNotification(notificationName as CFString, 0)
  }

  static func isSynthetic(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
  }
}
