import Testing

@testable import GestureCore

@Suite("Scroll presets")
struct ScrollPresetTests {
  @Test("120 Hz presets stay inside the settings ranges")
  func presetsStayInsideSettingsRanges() {
    for preset in ScrollPreset.allCases {
      let configuration = preset.configuration

      #expect((0.5...2.0).contains(configuration.speedMultiplier))
      #expect((0.75...1.5).contains(configuration.smoothnessMultiplier))
    }
  }

  @Test("balanced preset keeps the existing default behavior")
  func balancedPresetKeepsDefaultBehavior() {
    let configuration = ScrollPreset.balanced120.configuration

    #expect(configuration.speedMultiplier == 1.0)
    #expect(configuration.smoothnessMultiplier == 1.0)
    #expect(configuration.dynamicAccelerationEnabled)
  }

  @Test("event posting modes are independent from presets")
  func eventPostingModesAreIndependent() {
    #expect(ScrollEventPostingMode.fieldValues.displayName == "Standard")
    #expect(ScrollEventPostingMode.eventSourcePixels.displayName == "Compatibility")
  }

  @Test("matching returns a preset only for exact preset configuration")
  func matchingPreset() {
    #expect(
      ScrollPreset.matching(
        speedMultiplier: 1.20,
        smoothnessMultiplier: 0.90,
        dynamicAccelerationEnabled: true
      ) == .fast120
    )

    #expect(
      ScrollPreset.matching(
        speedMultiplier: 1.0,
        smoothnessMultiplier: 1.0,
        dynamicAccelerationEnabled: true
      ) == .balanced120
    )

    #expect(
      ScrollPreset.matching(
        speedMultiplier: 1.20,
        smoothnessMultiplier: 0.95,
        dynamicAccelerationEnabled: true
      ) == nil
    )
  }
}
