import Testing

@testable import GestureCore

@Suite("Fluid gesture plan")
struct FluidGesturePlanTests {
  @Test("left progress is positive with explicit lifecycle phases")
  func leftPlan() {
    let plan = fluidGesturePlan(direction: .left, changedFrameCount: 2)

    #expect(plan.map(\.phase) == [.mayBegin, .began, .changed, .changed, .ended])
    #expect(plan.map(\.progress) == [0, 0, 2.0 / 3.0, 4.0 / 3.0, 4.0 / 3.0])
  }

  @Test("right progress is negative")
  func rightPlan() {
    let plan = fluidGesturePlan(direction: .right, changedFrameCount: 2)

    #expect(plan.map(\.progress) == [0, 0, -2.0 / 3.0, -4.0 / 3.0, -4.0 / 3.0])
  }

  @Test("mouse displacement maps to signed and clamped fluid progress")
  func dragProgress() {
    #expect(fluidProgress(deltaX: -120, fullDistance: 240) == 2.0 / 3.0)
    #expect(fluidProgress(deltaX: 120, fullDistance: 240) == -2.0 / 3.0)
    #expect(fluidProgress(deltaX: -1_000, fullDistance: 240) == 4.0 / 3.0)
  }

  @Test("default full drag distance follows the captured display-width ratio")
  func defaultFullDistance() {
    #expect(fluidFullDistance(displayWidth: 1_920, customDistance: nil) == 1_920 * 0.52)
  }

  @Test("custom full drag distance overrides display calibration")
  func customFullDistance() {
    #expect(fluidFullDistance(displayWidth: 1_920, customDistance: 700) == 700)
  }

  @Test("release target commits direction or cancels to zero")
  func releaseTargets() {
    #expect(fluidReleaseTarget(for: .switchSpace(.left)) == 4.0 / 3.0)
    #expect(fluidReleaseTarget(for: .switchSpace(.right)) == -4.0 / 3.0)
    #expect(fluidReleaseTarget(for: .rightClick) == 0)
  }

  @Test("a strong flick commits when projected momentum crosses halfway")
  func fastFlickCommits() {
    #expect(
      fluidReleaseOutcome(
        deltaX: -45,
        velocityX: -2_500,
        directionalCoherence: 0.95,
        fullDistance: 1_000
      )
        == .switchSpace(.left))
  }

  @Test("moderate velocity near the original Space does not false-trigger")
  func moderateReleaseNearOriginCancels() {
    #expect(
      fluidReleaseOutcome(
        deltaX: -140,
        velocityX: -1_203,
        directionalCoherence: 1,
        fullDistance: 998.4
      )
        == .rightClick)
    #expect(abs(fluidProjectedDeltaX(deltaX: -140, velocityX: -1_203) + 380.6) < 0.001)
  }

  @Test("a slow drag commits only after crossing half the transition")
  func slowDragUsesHalfwayThreshold() {
    #expect(
      fluidReleaseOutcome(
        deltaX: 510,
        velocityX: 200,
        directionalCoherence: 1,
        fullDistance: 1_000
      )
        == .switchSpace(.right))
    #expect(
      fluidReleaseOutcome(
        deltaX: 490,
        velocityX: 200,
        directionalCoherence: 1,
        fullDistance: 1_000
      )
        == .rightClick)
  }

  @Test("release velocity opposite to displacement does not commit the wrong direction")
  func reversalCancels() {
    #expect(
      fluidReleaseOutcome(
        deltaX: -45,
        velocityX: 1_200,
        directionalCoherence: 1,
        fullDistance: 1_000
      )
        == .rightClick)
  }

  @Test("left-right shaking is not treated as a flick")
  func shakingCancels() {
    #expect(
      fluidReleaseOutcome(
        deltaX: 45,
        velocityX: 1_500,
        directionalCoherence: 0.2,
        fullDistance: 1_000
      )
        == .rightClick)
  }

  @Test("motion window measures flick speed and rejects shaking")
  func motionWindow() {
    var flick = FluidMotionTracker()
    flick.reset(timestamp: 0)
    flick.sample(deltaX: 20, timestamp: 20_000_000)
    let flickEstimate = flick.sample(deltaX: 45, timestamp: 40_000_000)
    #expect(flickEstimate.velocityX == 1_125)
    #expect(flickEstimate.directionalCoherence == 1)

    var shake = FluidMotionTracker()
    shake.reset(timestamp: 0)
    shake.sample(deltaX: 40, timestamp: 20_000_000)
    shake.sample(deltaX: -40, timestamp: 40_000_000)
    let shakeEstimate = shake.sample(deltaX: 45, timestamp: 60_000_000)
    #expect(shakeEstimate.directionalCoherence < 0.25)
  }

  @Test("faster releases use fewer settle frames")
  func adaptiveSettleDuration() {
    #expect(fluidSettleFrameCount(velocityX: 200) == 24)
    #expect(fluidSettleFrameCount(velocityX: 1_200) == 18)
    #expect(fluidSettleFrameCount(velocityX: 2_000) == 12)
  }

  @Test("cancel discards release momentum while commit preserves it")
  func cancelSettlesWithoutMomentum() {
    #expect(fluidSettleVelocity(for: .rightClick, releaseVelocityX: 1_200) == 0)
    #expect(
      fluidSettleVelocity(for: .switchSpace(.right), releaseVelocityX: 1_200) == 1_200)
  }

  @Test("settling interpolates to the final target")
  func settleProgress() {
    #expect(
      fluidSettleProgresses(from: 0.5, to: 1.0, frameCount: 2, velocityX: 0)
        == [0.75, 1.0])
    #expect(
      fluidSettleProgresses(from: 0.5, to: 1.0, frameCount: 2, velocityX: 1_200)
        == [0.9375, 1.0])
  }

  @Test("diagnostic progress logging is sampled independently of gesture frames")
  func progressLogSampling() {
    var sampler = TimestampRateLimiter(intervalNanoseconds: 100_000_000)
    let first = sampler.shouldEmit(timestamp: 0)
    let tooSoon = sampler.shouldEmit(timestamp: 8_000_000)
    let nextInterval = sampler.shouldEmit(timestamp: 100_000_000)
    let forced = sampler.shouldEmit(timestamp: 108_000_000, force: true)
    #expect(first)
    #expect(!tooSoon)
    #expect(nextInterval)
    #expect(forced)
  }
}
