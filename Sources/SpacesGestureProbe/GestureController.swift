import ApplicationServices
@preconcurrency import CoreGraphics
import GestureCore
import Foundation

private func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let controller = Unmanaged<GestureController>.fromOpaque(userInfo).takeUnretainedValue()
  return MainActor.assumeIsolated {
    controller.handle(type: type, event: event)
  }
}

@MainActor
final class GestureController {
  private let logger = EventLogger()
  private let fluidPoster = FluidGestureEventPoster()
  private var tracker = GestureTracker(threshold: 80.0) // Default threshold
  private var tap: CFMachPort?
  private var previousX: Double?
  private var lastGestureID: String?
  private var fluidStarted = false
  private var fluidProgressValue = 0.0
  private var fluidFullDistanceValue = 800.0
  private var fluidStartPoint: CGPoint?
  private var lastFluidPostTimestamp: UInt64?
  private var lastUpdateDeltaX: Double = 0.0
  private var fluidProgressLogLimiter = TimestampRateLimiter(
    intervalNanoseconds: 100_000_000
  )
  private var fluidMotionTracker = FluidMotionTracker()

  init() {}

  func start() throws {
    let eventTypes: [CGEventType] = [
      .rightMouseDown, .rightMouseDragged, .rightMouseUp
    ]
    let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: eventTapCallback,
      userInfo: pointer
    )
    guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw ControllerError.eventTapUnavailable
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    
    logger.write(
      "probe_started",
      [
        "mode": "private-drag",
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "tap": "session_active",
        "event_mask": "gesture_control",
      ])
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      logger.write("event_tap_reenabled", ["reason": "\(type.rawValue)"])
      return Unmanaged.passUnretained(event)
    }
    if InputPoster.isSynthetic(event) {
      return Unmanaged.passUnretained(event)
    }

    switch type {
    case .rightMouseDown:
      begin(at: event.location, timestamp: event.timestamp)
      return nil
    case .rightMouseDragged:
      guard tracker.isTracking else { return Unmanaged.passUnretained(event) }
      drag(to: event.location, timestamp: event.timestamp)
      return nil
    case .rightMouseUp:
      guard tracker.isTracking else { return Unmanaged.passUnretained(event) }
      finish(at: event.location, timestamp: event.timestamp)
      return nil
    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func begin(at point: CGPoint, timestamp: UInt64) {
    tracker.begin(at: point)
    previousX = point.x
    lastGestureID = UUID().uuidString
    fluidStarted = false
    fluidProgressValue = 0
    fluidStartPoint = point
    fluidFullDistanceValue = fluidFullDistance(
      displayWidth: displayWidth(containing: point),
      customDistance: nil
    )
    lastFluidPostTimestamp = nil
    fluidProgressLogLimiter.reset()
    fluidMotionTracker.reset(timestamp: timestamp)
    logger.write("gesture_began", ["gesture_id": lastGestureID!])
  }

  private func drag(to point: CGPoint, timestamp: UInt64) {
    guard let update = tracker.move(to: point) else { return }
    updateFluidDrag(update, timestamp: timestamp)
    self.previousX = point.x
  }

  private func finish(at point: CGPoint, timestamp: UInt64) {
    let completion = tracker.end(at: point)
    var outcome = completion.outcome
    let releaseDeltaX = Double(completion.update?.deltaX ?? 0)
    
    if let finalUpdate = completion.update {
      updateFluidDrag(finalUpdate, timestamp: timestamp, forcePost: true)
      let motion = fluidMotionTracker.estimate
      outcome = fluidReleaseOutcome(
        deltaX: Double(finalUpdate.deltaX),
        velocityX: motion.velocityX,
        directionalCoherence: motion.directionalCoherence,
        fullDistance: fluidFullDistanceValue
      )
    }
    finishFluidDrag(
      outcome: outcome,
      releasePoint: point,
      motion: fluidMotionTracker.estimate,
      releaseDeltaX: releaseDeltaX
    )
    previousX = nil
  }

  private func updateFluidDrag(
    _ update: GestureUpdate,
    timestamp: UInt64,
    forcePost: Bool = false
  ) {
    guard let location = fluidStartPoint else { return }
    fluidMotionTracker.sample(deltaX: Double(update.deltaX), timestamp: timestamp)
    let activationDistance = min(80.0, 6.0)
    guard fluidStarted || abs(update.deltaX) >= activationDistance else { return }

    let screenWidth = displayWidth(containing: location)
    let scaleH = 2.0 / (screenWidth + 63.0)
    
    if !fluidStarted {
      _ = fluidPoster.post(phase: .mayBegin, progress: 0, location: location)
      _ = fluidPoster.post(phase: .began, progress: 0, location: location)
      fluidStarted = true
      fluidProgressValue = 0
      lastUpdateDeltaX = 0.0
      logger.write(
        "fluid_drag_began",
        [
          "gesture_id": lastGestureID!,
          "display_width": "\(screenWidth)"
        ])
    }

    lastUpdateDeltaX = Double(update.deltaX)

    fluidProgressValue = Double(update.deltaX) * scaleH * -1.0

    if !forcePost,
      let lastFluidPostTimestamp,
      timestamp >= lastFluidPostTimestamp,
      timestamp - lastFluidPostTimestamp < 8_000_000
    {
      return
    }
    lastFluidPostTimestamp = timestamp
    
    let posted = fluidPoster.post(
      phase: .changed,
      progress: fluidProgressValue,
      location: location
    )
    if posted, fluidProgressLogLimiter.shouldEmit(timestamp: timestamp, force: forcePost) {
      logger.write(
        "fluid_drag_progress",
        ["progress": "\(fluidProgressValue)", "gesture_id": lastGestureID!])
    }
  }

  private func finishFluidDrag(
    outcome: GestureOutcome,
    releasePoint: CGPoint,
    motion: FluidMotionEstimate,
    releaseDeltaX: Double
  ) {
    guard fluidStarted, let location = fluidStartPoint else {
      if outcome == .rightClick {
        InputPoster.rightClick(at: releasePoint)
      }
      logger.write(
        "gesture_ended",
        ["gesture_id": lastGestureID!, "outcome": outcome.logName])
      return
    }

    fluidStarted = false
    
    let screenWidth = displayWidth(containing: location)
    let scaleH = 2.0 / (screenWidth + 63.0)
    
    let lastFrameDeltaX = motion.velocityX / 60.0
    let exitSpeed = lastFrameDeltaX * scaleH * -100.0
    
    let isCancelled: Bool
    if (motion.velocityX < -50 && fluidProgressValue < 0) || (motion.velocityX > 50 && fluidProgressValue > 0) {
      isCancelled = true
    } else {
      isCancelled = abs(fluidProgressValue) < 0.5 && abs(motion.velocityX) < 200
    }
    
    let phase: FluidGesturePhase = isCancelled ? .cancelled : .ended
    
    _ = fluidPoster.post(phase: phase, progress: fluidProgressValue, velocity: exitSpeed, location: location)

    logger.write(
      "fluid_drag_ended",
      [
        "gesture_id": lastGestureID!,
        "outcome": isCancelled ? "cancelled" : "ended",
        "release_velocity_x": "\(motion.velocityX)",
        "release_delta_x": "\(releaseDeltaX)",
        "exit_speed": "\(exitSpeed)",
        "progress": "\(fluidProgressValue)"
      ]
    )
  }

  private func displayWidth(containing point: CGPoint) -> Double {
    var display = CGDirectDisplayID()
    var count: UInt32 = 0
    let result = CGGetDisplaysWithPoint(point, 1, &display, &count)
    guard result == .success, count > 0 else { return 1_440 }
    return Double(CGDisplayBounds(display).width)
  }
}

enum ControllerError: Error {
  case eventTapUnavailable
}
