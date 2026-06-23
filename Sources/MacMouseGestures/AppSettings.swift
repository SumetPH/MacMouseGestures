import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
  struct Values {
    let isEnabled: Bool
    let scrollSpeed: Double
    let scrollSmoothness: Double
  }

  private enum Key {
    static let isEnabled = "isEnabled"
    static let scrollSpeed = "scrollSpeed"
    static let scrollSmoothness = "scrollSmoothness"
  }

  static let defaultScrollSpeed = 1.0
  static let defaultScrollSmoothness = 1.0
  static let scrollSpeedRange = 0.5...2.0
  static let scrollSmoothnessRange = 0.75...1.5

  @Published var isEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var scrollSpeed: Double {
    didSet { saveAndNotify() }
  }
  @Published var scrollSmoothness: Double {
    didSet { saveAndNotify() }
  }
  @Published var launchAtLogin: Bool {
    didSet { updateLaunchAtLogin() }
  }

  var onChange: ((Values) -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
    scrollSpeed = Self.loadValue(
      from: defaults,
      key: Key.scrollSpeed,
      defaultValue: Self.defaultScrollSpeed,
      range: Self.scrollSpeedRange
    )
    scrollSmoothness = Self.loadValue(
      from: defaults,
      key: Key.scrollSmoothness,
      defaultValue: Self.defaultScrollSmoothness,
      range: Self.scrollSmoothnessRange
    )
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  var values: Values {
    Values(
      isEnabled: isEnabled,
      scrollSpeed: scrollSpeed,
      scrollSmoothness: scrollSmoothness
    )
  }

  func resetScrolling() {
    scrollSpeed = Self.defaultScrollSpeed
    scrollSmoothness = Self.defaultScrollSmoothness
  }

  private func saveAndNotify() {
    defaults.set(isEnabled, forKey: Key.isEnabled)
    defaults.set(scrollSpeed, forKey: Key.scrollSpeed)
    defaults.set(scrollSmoothness, forKey: Key.scrollSmoothness)
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

  private static func loadValue(
    from defaults: UserDefaults,
    key: String,
    defaultValue: Double,
    range: ClosedRange<Double>
  ) -> Double {
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return min(max(defaults.double(forKey: key), range.lowerBound), range.upperBound)
  }
}
