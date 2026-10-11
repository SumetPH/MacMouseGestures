import AppKit
import ApplicationServices
import Foundation

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
  private let menuBarController: MenuBarController

  init(menuBarController: MenuBarController) {
    self.menuBarController = menuBarController
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !Self.wasLaunchedAsLoginItem() else { return }
    menuBarController.handleApplicationOpen()
  }

  // Only valid while handling the launch ('oapp') Apple event, i.e. in applicationDidFinishLaunching.
  private static func wasLaunchedAsLoginItem() -> Bool {
    let event = NSAppleEventManager.shared().currentAppleEvent
    return event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    menuBarController.handleApplicationOpen()
    return true
  }
}

do {
  guard PermissionManager.requestAccessibility() else {
    fputs(
      "Accessibility permission is required. Grant it in System Settings, then run again.\n", stderr
    )
    exit(2)
  }

  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)

  let controller = GestureController()
  try controller.start()

  let settings = AppSettings()
  controller.apply(settings: settings.values)
  settings.onChange = { [weak controller] values in
    controller?.apply(settings: values)
  }
  let menuBarController = MenuBarController(settings: settings)
  let applicationDelegate = ApplicationDelegate(menuBarController: menuBarController)
  application.delegate = applicationDelegate

  withExtendedLifetime((controller, settings, menuBarController, applicationDelegate)) {
    application.run()
  }
} catch {
  fputs("Error: \(error)\n", stderr)
  exit(1)
}
