public enum FluidGesturePhase: Equatable, Sendable {
  case mayBegin
  case began
  case changed
  case ended
  case cancelled
}

public struct FluidGestureStep: Equatable, Sendable {
  public let phase: FluidGesturePhase
  public let progress: Double

  public init(phase: FluidGesturePhase, progress: Double) {
    self.phase = phase
    self.progress = progress
  }
}

public struct FluidMotionEstimate: Equatable, Sendable {
  public let velocityX: Double
  public let directionalCoherence: Double
}

public struct FluidMotionTracker: Sendable {
  private struct Sample: Sendable {
    let deltaX: Double
    let timestamp: UInt64
  }

  private let windowNanoseconds: UInt64
  private var samples: [Sample] = []

  public init(windowMilliseconds: UInt64 = 120) {
    precondition(windowMilliseconds > 0)
    windowNanoseconds = windowMilliseconds * 1_000_000
  }

  public mutating func reset(timestamp: UInt64) {
    samples = [Sample(deltaX: 0, timestamp: timestamp)]
  }

  @discardableResult
  public mutating func sample(deltaX: Double, timestamp: UInt64) -> FluidMotionEstimate {
    samples.append(Sample(deltaX: deltaX, timestamp: timestamp))
    samples.removeAll { sample in
      timestamp >= sample.timestamp && timestamp - sample.timestamp > windowNanoseconds
    }
    return estimate
  }

  public var estimate: FluidMotionEstimate {
    guard let first = samples.first, let last = samples.last,
      last.timestamp > first.timestamp
    else { return FluidMotionEstimate(velocityX: 0, directionalCoherence: 0) }

    let elapsed = Double(last.timestamp - first.timestamp) / 1_000_000_000
    let netMovement = last.deltaX - first.deltaX
    var pathLength = 0.0
    for index in 1..<samples.count {
      pathLength += abs(samples[index].deltaX - samples[index - 1].deltaX)
    }
    return FluidMotionEstimate(
      velocityX: netMovement / elapsed,
      directionalCoherence: pathLength > 0 ? abs(netMovement) / pathLength : 0
    )
  }
}

public struct TimestampRateLimiter: Sendable {
  private let intervalNanoseconds: UInt64
  private var lastEmissionTimestamp: UInt64?

  public init(intervalNanoseconds: UInt64) {
    precondition(intervalNanoseconds > 0)
    self.intervalNanoseconds = intervalNanoseconds
  }

  public mutating func reset() {
    lastEmissionTimestamp = nil
  }

  public mutating func shouldEmit(timestamp: UInt64, force: Bool = false) -> Bool {
    if force {
      lastEmissionTimestamp = timestamp
      return true
    }
    guard let lastEmissionTimestamp else {
      self.lastEmissionTimestamp = timestamp
      return true
    }
    guard timestamp >= lastEmissionTimestamp,
      timestamp - lastEmissionTimestamp >= intervalNanoseconds
    else { return false }
    self.lastEmissionTimestamp = timestamp
    return true
  }
}

public func fluidGesturePlan(
  direction: SyntheticSwipeDirection,
  changedFrameCount: Int
) -> [FluidGestureStep] {
  precondition(changedFrameCount > 0)
  let sign = direction == .left ? 1.0 : -1.0
  let target = sign * 4.0 / 3.0
  var steps = [
    FluidGestureStep(phase: .mayBegin, progress: 0),
    FluidGestureStep(phase: .began, progress: 0),
  ]
  for frame in 1...changedFrameCount {
    steps.append(
      FluidGestureStep(
        phase: .changed,
        progress: target * Double(frame) / Double(changedFrameCount)
      ))
  }
  steps.append(FluidGestureStep(phase: .ended, progress: target))
  return steps
}

public func fluidProgress(deltaX: Double, fullDistance: Double) -> Double {
  precondition(fullDistance > 0)
  let target = (-deltaX * 4.0) / (fullDistance * 3.0)
  return min(max(target, -4.0 / 3.0), 4.0 / 3.0)
}

/// Calibrated for a lighter, more responsive feel: one completed transition
/// consumes approximately 30% of the width of the display receiving the gesture.
/// This maps to ~576 points on a 1920pt display (close to the preferred 600),
/// and ~405 points on a 1352pt MacBook Pro display.
public func fluidFullDistance(displayWidth: Double, customDistance: Double?) -> Double {
  precondition(displayWidth > 0)
  if let customDistance {
    precondition(customDistance > 0)
    return customDistance
  }
  return displayWidth * 0.30
}

public func fluidReleaseTarget(for outcome: GestureOutcome) -> Double {
  switch outcome {
  case .switchSpace(.left): 4.0 / 3.0
  case .switchSpace(.right): -4.0 / 3.0
  case .none, .rightClick: 0
  }
}

public func fluidReleaseOutcome(
  deltaX: Double,
  velocityX: Double,
  directionalCoherence: Double,
  fullDistance: Double,
  minimumFlickDistance: Double = 30,
  flickVelocityThreshold: Double = 900,
  minimumFlickCoherence: Double = 0.75,
  momentumPredictionDuration: Double = 0.10,
  minimumFlickProgress: Double = 0.25
) -> GestureOutcome {
  precondition(fullDistance > 0)
  precondition(minimumFlickDistance >= 0)
  precondition(flickVelocityThreshold > 0)
  precondition((0...1).contains(minimumFlickCoherence))
  precondition(momentumPredictionDuration >= 0)
  precondition(minimumFlickProgress >= 0)

  let commitDistance = fullDistance * 0.5
  let commitsByDistance = abs(deltaX) >= commitDistance
  let qualifiesForMomentum =
    abs(deltaX) >= minimumFlickDistance
    && abs(velocityX) >= flickVelocityThreshold
    && directionalCoherence >= minimumFlickCoherence
    && deltaX * velocityX > 0
  let projectedDeltaX = fluidProjectedDeltaX(
    deltaX: deltaX,
    velocityX: velocityX,
    predictionDuration: momentumPredictionDuration
  )
  // For momentum/flick commits, require the user to have dragged at least
  // minimumFlickProgress of the full transition distance. This prevents
  // slow drags with snap releases from triggering switches — the velocity
  // spike on release looks like a flick but the drag barely moved.
  let meetsFlickProgress = abs(deltaX) >= fullDistance * minimumFlickProgress
  let commitsByFlick = qualifiesForMomentum && meetsFlickProgress
    && abs(projectedDeltaX) >= commitDistance
  guard commitsByDistance || commitsByFlick else { return .rightClick }
  return .switchSpace(deltaX < 0 ? .left : .right)
}

public func fluidProjectedDeltaX(
  deltaX: Double,
  velocityX: Double,
  predictionDuration: Double = 0.20
) -> Double {
  precondition(predictionDuration >= 0)
  return deltaX + velocityX * predictionDuration
}

public func fluidSettleFrameCount(velocityX: Double) -> Int {
  switch abs(velocityX) {
  case 1_800...: 14
  case 900...: 20
  default: 24
  }
}

public func fluidSettleVelocity(
  for outcome: GestureOutcome,
  releaseVelocityX: Double
) -> Double {
  switch outcome {
  case .switchSpace: releaseVelocityX
  case .none, .rightClick: 0
  }
}

public func fluidSettleProgresses(
  from start: Double,
  to target: Double,
  frameCount: Int,
  velocityX: Double = 0
) -> [Double] {
  precondition(frameCount > 0)
  return (1...frameCount).map { frame in
    let time = Double(frame) / Double(frameCount)
    let interpolation: Double
    if abs(velocityX) >= 900 {
      let remaining = 1 - time
      // Quadratic ease-out to prevent an overly aggressive initial jump
      // which makes fast flicks feel "too fast" and jumpy on 4K 120Hz displays.
      interpolation = 1 - remaining * remaining
    } else {
      interpolation = time * time * (3 - 2 * time)
    }
    return start + (target - start) * interpolation
  }
}
