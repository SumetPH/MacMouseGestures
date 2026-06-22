import Foundation

/// Mac Mouse Fix's Smoothness: Regular / Speed: Medium acceleration curve.
public func regularMediumPixelsPerTick(
  scrollSpeed: Double,
  displayScale: Double,
  speedMultiplier: Double = 1
) -> Double {
  precondition(displayScale > 0)
  precondition(speedMultiplier > 0)

  let minimumScrollSpeed = 1.0 / 0.160
  let maximumScrollSpeed = 1.0 / 0.015
  let minimumPixelsPerTick = 60.0
  let maximumPixelsPerTick = 120.0 * (0.9 + 0.1 * displayScale)
  let progress = min(
    max((scrollSpeed - minimumScrollSpeed) / (maximumScrollSpeed - minimumScrollSpeed), 0),
    1
  )
  let pixelsPerTick = minimumPixelsPerTick
    + progress * (maximumPixelsPerTick - minimumPixelsPerTick)
  return pixelsPerTick * speedMultiplier
}

/// Base duration of Mac Mouse Fix's low-inertia hybrid curve.
public func regularScrollBaseDuration(
  timeBetweenTicks: Double,
  smoothnessMultiplier: Double = 1
) -> Double {
  precondition(smoothnessMultiplier > 0)
  let slowestTickInterval = 0.160
  let fastestTickInterval = 0.001
  let progress = min(
    max(
      (slowestTickInterval - timeBetweenTicks)
        / (slowestTickInterval - fastestTickInterval),
      0
    ),
    1
  )
  let curvature = 4.0
  let curvedProgress = (exp(progress * curvature) - 1) / (exp(curvature) - 1)
  let milliseconds = 180.0 - curvedProgress * (180.0 - 110.0)
  return milliseconds / 1_000.0 * smoothnessMultiplier
}

public func scrollDurationAlignedToFrames(
  _ duration: Double,
  frameDuration: Double
) -> Double {
  precondition(duration >= 0)
  precondition(frameDuration > 0)
  return ceil(duration / frameDuration - 1e-9) * frameDuration
}
