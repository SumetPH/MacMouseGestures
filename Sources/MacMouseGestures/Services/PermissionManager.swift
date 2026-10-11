import ApplicationServices

enum PermissionManager {
  /// Returns whether the process is trusted for Accessibility, prompting the user if it is not.
  static func requestAccessibility() -> Bool {
    let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(prompt)
  }
}
