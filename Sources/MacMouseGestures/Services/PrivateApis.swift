import CoreFoundation

// Private Dock/HIServices symbol, resolved at link time (not App Store safe).
// Used to trigger Mission Control and Application Windows (App Exposé).
// The raw CGEventField-based DockSwipe construction lives in the MacMouseGesturesBridge target.
@_silgen_name("CoreDockSendNotification")
func CoreDockSendNotification(_ name: CFString, _ unknown: Int)
