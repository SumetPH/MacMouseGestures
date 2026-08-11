import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
  struct Values {
    let gesturesEnabled: Bool
    let mouseButton3Number: Int64
    let mouseButton4Number: Int64
    let mouseButton3Action: MouseButtonAction
    let mouseButton4Action: MouseButtonAction
  }

  private enum Key {
    static let gesturesEnabled = "gesturesEnabled"
    static let mouseButton3Number = "mouseButton3Number"
    static let mouseButton4Number = "mouseButton4Number"
    static let mouseButton3Action = "mouseButton3Action"
    static let mouseButton4Action = "mouseButton4Action"
  }

  @Published var gesturesEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var launchAtLogin: Bool {
    didSet { updateLaunchAtLogin() }
  }
  @Published var mouseButton3Number: Int64 {
    didSet { saveAndNotify() }
  }
  @Published var mouseButton4Number: Int64 {
    didSet { saveAndNotify() }
  }
  @Published var mouseButton3Action: MouseButtonAction {
    didSet { saveAndNotify() }
  }
  @Published var mouseButton4Action: MouseButtonAction {
    didSet { saveAndNotify() }
  }

  var onChange: ((Values) -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    gesturesEnabled = defaults.object(forKey: Key.gesturesEnabled) as? Bool ?? true
    launchAtLogin = SMAppService.mainApp.status == .enabled
    mouseButton3Number = Self.loadButtonNumber(
      defaults: defaults,
      key: Key.mouseButton3Number,
      defaultValue: 3
    )
    mouseButton4Number = Self.loadButtonNumber(
      defaults: defaults,
      key: Key.mouseButton4Number,
      defaultValue: 4
    )
    mouseButton3Action = Self.loadAction(defaults: defaults, key: Key.mouseButton3Action)
    mouseButton4Action = Self.loadAction(defaults: defaults, key: Key.mouseButton4Action)
  }

  var values: Values {
    Values(
      gesturesEnabled: gesturesEnabled,
      mouseButton3Number: mouseButton3Number,
      mouseButton4Number: mouseButton4Number,
      mouseButton3Action: mouseButton3Action,
      mouseButton4Action: mouseButton4Action
    )
  }

  private func saveAndNotify() {
    defaults.set(gesturesEnabled, forKey: Key.gesturesEnabled)
    defaults.set(mouseButton3Number, forKey: Key.mouseButton3Number)
    defaults.set(mouseButton4Number, forKey: Key.mouseButton4Number)
    defaults.set(mouseButton3Action.rawValue, forKey: Key.mouseButton3Action)
    defaults.set(mouseButton4Action.rawValue, forKey: Key.mouseButton4Action)
    onChange?(values)
  }

  private static func loadButtonNumber(
    defaults: UserDefaults,
    key: String,
    defaultValue: Int64
  ) -> Int64 {
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return Int64(defaults.integer(forKey: key))
  }

  private static func loadAction(defaults: UserDefaults, key: String) -> MouseButtonAction {
    guard let rawValue = defaults.string(forKey: key) else { return .none }
    return MouseButtonAction(rawValue: rawValue) ?? .none
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
