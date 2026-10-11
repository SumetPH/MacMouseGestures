import CoreFoundation
import Darwin

// Private Dock/HIServices symbol (not App Store safe), resolved at runtime so a missing
// symbol disables the action instead of preventing launch.
// Used to trigger Mission Control and Application Windows (App Exposé).
// The raw CGEventField-based DockSwipe construction lives in the MacMouseGesturesBridge target.
private typealias CoreDockSendNotificationFn = @convention(c) (CFString, Int) -> Void

private let coreDockSendNotificationFn: CoreDockSendNotificationFn? = {
  guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
    return nil
  }
  return unsafeBitCast(symbol, to: CoreDockSendNotificationFn.self)
}()

/// Returns false when the private symbol is unavailable on this macOS version.
@discardableResult
func CoreDockSendNotification(_ name: CFString, _ unknown: Int) -> Bool {
  guard let fn = coreDockSendNotificationFn else { return false }
  fn(name, unknown)
  return true
}
