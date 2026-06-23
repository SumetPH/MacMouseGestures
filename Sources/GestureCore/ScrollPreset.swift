import Foundation

public enum ScrollEventPostingMode: String, CaseIterable, Sendable {
  case fieldValues
  case eventSourcePixels

  public var displayName: String {
    switch self {
    case .fieldValues:
      return "Standard"
    case .eventSourcePixels:
      return "Compatibility"
    }
  }

  public var detail: String {
    switch self {
    case .fieldValues:
      return "Direct pixel and line scroll fields."
    case .eventSourcePixels:
      return "CoreGraphics pixel-unit event source."
    }
  }
}

public struct ScrollPresetConfiguration: Equatable, Sendable {
  public let speedMultiplier: Double
  public let smoothnessMultiplier: Double
  public let dynamicAccelerationEnabled: Bool

  public init(
    speedMultiplier: Double,
    smoothnessMultiplier: Double,
    dynamicAccelerationEnabled: Bool
  ) {
    precondition(speedMultiplier > 0)
    precondition(smoothnessMultiplier > 0)
    self.speedMultiplier = speedMultiplier
    self.smoothnessMultiplier = smoothnessMultiplier
    self.dynamicAccelerationEnabled = dynamicAccelerationEnabled
  }
}

/// Presets tuned around a 120 Hz display and a high-polling mouse wheel.
public enum ScrollPreset: String, CaseIterable, Identifiable, Sendable {
  case balanced120
  case precise120
  case fast120
  case glide120

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .balanced120:
      return "120 Hz Balanced"
    case .precise120:
      return "120 Hz Precise"
    case .fast120:
      return "120 Hz Fast"
    case .glide120:
      return "120 Hz Glide"
    }
  }

  public var detail: String {
    switch self {
    case .balanced120:
      return "Default distance, frame-aligned smoothing, acceleration on."
    case .precise120:
      return "Shorter distance and more smoothing for reading or code."
    case .fast120:
      return "More distance with a shorter tail for fast navigation."
    case .glide120:
      return "Longer smoothing with acceleration off for steady long pages."
    }
  }

  public var configuration: ScrollPresetConfiguration {
    switch self {
    case .balanced120:
      return ScrollPresetConfiguration(
        speedMultiplier: 1.00,
        smoothnessMultiplier: 1.00,
        dynamicAccelerationEnabled: true
      )
    case .precise120:
      return ScrollPresetConfiguration(
        speedMultiplier: 0.85,
        smoothnessMultiplier: 1.20,
        dynamicAccelerationEnabled: false
      )
    case .fast120:
      return ScrollPresetConfiguration(
        speedMultiplier: 1.20,
        smoothnessMultiplier: 0.90,
        dynamicAccelerationEnabled: true
      )
    case .glide120:
      return ScrollPresetConfiguration(
        speedMultiplier: 1.05,
        smoothnessMultiplier: 1.35,
        dynamicAccelerationEnabled: false
      )
    }
  }

  public func matches(
    speedMultiplier: Double,
    smoothnessMultiplier: Double,
    dynamicAccelerationEnabled: Bool,
    tolerance: Double = 0.000_001
  ) -> Bool {
    let configuration = configuration
    return abs(configuration.speedMultiplier - speedMultiplier) <= tolerance
      && abs(configuration.smoothnessMultiplier - smoothnessMultiplier) <= tolerance
      && configuration.dynamicAccelerationEnabled == dynamicAccelerationEnabled
  }

  public static func matching(
    speedMultiplier: Double,
    smoothnessMultiplier: Double,
    dynamicAccelerationEnabled: Bool
  ) -> ScrollPreset? {
    allCases.first {
      $0.matches(
        speedMultiplier: speedMultiplier,
        smoothnessMultiplier: smoothnessMultiplier,
        dynamicAccelerationEnabled: dynamicAccelerationEnabled
      )
    }
  }
}
