import Combine
import Foundation
import GestureCore
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
  struct Values {
    let gesturesEnabled: Bool
    let scrollingEnabled: Bool
    let scrollSpeed: Double
    let scrollSmoothness: Double
    let dynamicAccelerationEnabled: Bool
    let scrollEventPostingMode: ScrollEventPostingMode
  }

  private enum Key {
    static let gesturesEnabled = "gesturesEnabled"
    static let scrollingEnabled = "scrollingEnabled"
    static let scrollSpeed = "scrollSpeed"
    static let scrollSmoothness = "scrollSmoothness"
    static let dynamicAccelerationEnabled = "dynamicAccelerationEnabled"
    static let scrollEventPostingMode = "scrollEventPostingMode"
  }

  static let defaultScrollSpeed = 1.0
  static let defaultScrollSmoothness = 1.0
  static let scrollSpeedRange = 0.5...2.0
  static let scrollSmoothnessRange = 0.75...1.5
  static let customScrollPresetID = "custom"

  @Published var gesturesEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var scrollingEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var scrollSpeed: Double {
    didSet { saveAndNotify() }
  }
  @Published var scrollSmoothness: Double {
    didSet { saveAndNotify() }
  }
  @Published var dynamicAccelerationEnabled: Bool {
    didSet { saveAndNotify() }
  }
  @Published var scrollEventPostingMode: ScrollEventPostingMode {
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
    scrollingEnabled = defaults.object(forKey: Key.scrollingEnabled) as? Bool ?? true
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
    dynamicAccelerationEnabled = defaults.object(forKey: Key.dynamicAccelerationEnabled) as? Bool ?? true
    scrollEventPostingMode = Self.loadScrollEventPostingMode(from: defaults)
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  var values: Values {
    Values(
      gesturesEnabled: gesturesEnabled,
      scrollingEnabled: scrollingEnabled,
      scrollSpeed: scrollSpeed,
      scrollSmoothness: scrollSmoothness,
      dynamicAccelerationEnabled: dynamicAccelerationEnabled,
      scrollEventPostingMode: scrollEventPostingMode
    )
  }

  var selectedScrollPreset: ScrollPreset? {
    ScrollPreset.matching(
      speedMultiplier: scrollSpeed,
      smoothnessMultiplier: scrollSmoothness,
      dynamicAccelerationEnabled: dynamicAccelerationEnabled
    )
  }

  var scrollPresetSelectionID: String {
    selectedScrollPreset?.id ?? Self.customScrollPresetID
  }

  func applyScrollPreset(_ preset: ScrollPreset) {
    let configuration = preset.configuration
    scrollSpeed = configuration.speedMultiplier
    scrollSmoothness = configuration.smoothnessMultiplier
    dynamicAccelerationEnabled = configuration.dynamicAccelerationEnabled
  }

  func resetScrolling() {
    applyScrollPreset(.balanced120)
    scrollEventPostingMode = .fieldValues
  }

  private func saveAndNotify() {
    defaults.set(gesturesEnabled, forKey: Key.gesturesEnabled)
    defaults.set(scrollingEnabled, forKey: Key.scrollingEnabled)
    defaults.set(scrollSpeed, forKey: Key.scrollSpeed)
    defaults.set(scrollSmoothness, forKey: Key.scrollSmoothness)
    defaults.set(dynamicAccelerationEnabled, forKey: Key.dynamicAccelerationEnabled)
    defaults.set(scrollEventPostingMode.rawValue, forKey: Key.scrollEventPostingMode)
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

  private static func loadScrollEventPostingMode(from defaults: UserDefaults) -> ScrollEventPostingMode {
    guard let rawValue = defaults.string(forKey: Key.scrollEventPostingMode),
      let mode = ScrollEventPostingMode(rawValue: rawValue)
    else { return .fieldValues }
    return mode
  }
}
