import AppKit
import ApplicationServices
import Foundation

do {
  let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
  guard AXIsProcessTrustedWithOptions(prompt) else {
    fputs(
      "Accessibility permission is required. Grant it in System Settings, then run again.\n", stderr
    )
    exit(2)
  }

  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)
  
  let controller = GestureController()
  try controller.start()
  
  withExtendedLifetime(controller) {
    application.run()
  }
} catch {
  fputs("Error: \(error)\n", stderr)
  exit(1)
}
