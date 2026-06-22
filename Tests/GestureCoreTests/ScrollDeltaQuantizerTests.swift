import Testing

@testable import GestureCore

@Suite("Smooth scroll delta quantizer")
struct ScrollDeltaQuantizerTests {
  @Test("regular medium uses Mac Mouse Fix distance at slow and fast wheel speeds")
  func regularMediumDistance() {
    #expect(regularMediumPixelsPerTick(scrollSpeed: 6.25, displayScale: 1) == 60)
    #expect(regularMediumPixelsPerTick(scrollSpeed: 66.6666666667, displayScale: 1) == 120)
  }

  @Test("regular smoothness slows single ticks enough to remain visually trackable")
  func regularAnimationDuration() {
    #expect(regularScrollBaseDuration(timeBetweenTicks: 0.160) == 0.180)
    #expect(abs(regularScrollBaseDuration(timeBetweenTicks: 0.001) - 0.110) < 0.000_001)
  }

  @Test("regular medium applies Mac Mouse Fix display scaling only to maximum speed")
  func regularMediumDisplayScaling() {
    #expect(regularMediumPixelsPerTick(scrollSpeed: 6.25, displayScale: 2) == 60)
    #expect(regularMediumPixelsPerTick(scrollSpeed: 66.6666666667, displayScale: 2) == 132)
  }

  @Test("scroll speed multiplier changes distance without changing the base curve")
  func scrollSpeedMultiplier() {
    #expect(
      regularMediumPixelsPerTick(
        scrollSpeed: 6.25,
        displayScale: 1,
        speedMultiplier: 1.5
      ) == 90
    )
  }

  @Test("smoothness multiplier scales animation duration")
  func smoothnessMultiplier() {
    #expect(
      abs(
        regularScrollBaseDuration(
          timeBetweenTicks: 0.160,
          smoothnessMultiplier: 1.25
        ) - 0.225
      ) < 0.000_001
    )
  }

  @Test("animation duration is rounded to whole 120 Hz frames")
  func durationUsesWholeFrames() {
    let frameDuration = 1.0 / 120.0
    let roundedDuration = scrollDurationAlignedToFrames(0.245, frameDuration: frameDuration)

    #expect(abs(roundedDuration - 0.250) < 0.000_001)
    #expect(scrollDurationAlignedToFrames(roundedDuration, frameDuration: frameDuration) == roundedDuration)
  }

  @Test("small 120 Hz frame deltas are emitted without changing total distance")
  func smallFrameDeltasPreserveDistance() {
    var quantizer = BiasedDeltaQuantizer()

    let output = (0..<12).map { _ in quantizer.quantize(0.25) }

    #expect(output.first == 1)
    #expect(output.reduce(0, +) == 3)
    #expect(output.filter { $0 != 0 }.count == 3)
  }

  @Test("final frame does not add the unposted tail twice")
  func finalFrameDoesNotDuplicateTail() {
    var quantizer = BiasedDeltaQuantizer()

    let output = [1.4, 1.4, 1.2].map { quantizer.quantize($0) }

    #expect(output.reduce(0, +) == 4)
  }

  @Test("negative deltas preserve sign and distance")
  func negativeDeltasPreserveDistance() {
    var quantizer = BiasedDeltaQuantizer()

    let output = (0..<8).map { _ in quantizer.quantize(-0.25) }

    #expect(output.first == -1)
    #expect(output.reduce(0, +) == -2)
  }
}
