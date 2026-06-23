import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
  struct Values {
    let gesturesEnabled: Bool
  }

  private enum Key {
    static let gesturesEnabled = "gesturesEnabled"
  }

  @Published var gesturesEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var launchAtLogin: Bool {
    didSet { updateLaunchAtLogin() }
  }

  var onChange: ((Values) -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    gesturesEnabled = defaults.object(forKey: Key.gesturesEnabled) as? Bool ?? true
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  var values: Values {
    Values(
      gesturesEnabled: gesturesEnabled
    )
  }

  private func saveAndNotify() {
    defaults.set(gesturesEnabled, forKey: Key.gesturesEnabled)
    onChange?(values)
  }

  private func updateLaunchAtLogin() {
    let service = SMAppService.mainApp
    if launchAtLogin {
      if service.status != .enabled {
        do {
          try service.register()
        } catch {
          print("Failed to register SMAppService: \(error)")
        }
      }
    } else {
      if service.status == .enabled {
        do {
          try service.unregister()
        } catch {
          print("Failed to unregister SMAppService: \(error)")
        }
      }
    }
  }
}
