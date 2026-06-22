import ApplicationServices
@preconcurrency import CoreGraphics
import GestureCore

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

private struct PendingFluidSettle {
  let location: CGPoint
  let target: Double
  let gestureID: String
  let outcome: GestureOutcome
  let motion: FluidMotionEstimate
  let releaseDeltaX: Double
}

@MainActor
final class GestureController {
  private let configuration: Configuration
  private let logger = EventLogger()
  private let scrollPoster: ScrollEventPoster
  private let fluidPoster = FluidGestureEventPoster()
  private let overlay: OverlayController?
  private let nativeRecorder: NativeGestureRecorder
  private var tracker: GestureTracker
  private var tap: CFMachPort?
  private var scrollStarted = false
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

  init(configuration: Configuration) {
    self.configuration = configuration
    tracker = GestureTracker(threshold: configuration.threshold)
    scrollPoster = ScrollEventPoster(scale: configuration.scrollScale)
    overlay = configuration.showsOverlay ? OverlayController() : nil
    nativeRecorder = NativeGestureRecorder(logger: logger)
  }

  func start() throws {
    let mask: CGEventMask
    if configuration.mode == .nativeRecord {
      mask = .max
    } else {
      let eventTypes: [CGEventType] = [
        .rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown, .keyUp, .flagsChanged,
      ]
      mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: configuration.mode == .nativeRecord ? .listenOnly : .defaultTap,
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
        "mode": configuration.mode.rawValue,
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "tap": configuration.mode == .nativeRecord ? "session_listen_only" : "session_active",
        "event_mask": configuration.mode == .nativeRecord ? "all" : "gesture_control",
      ])
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      logger.write("event_tap_reenabled", ["reason": "\(type.rawValue)"])
      return Unmanaged.passUnretained(event)
    }
    if configuration.mode == .nativeRecord {
      nativeRecorder.recordEnvelope(type: type, event: event)
      if NativeGestureRecorder.shouldRecord(type: type) {
        nativeRecorder.record(type: type, event: event)
      }
      return Unmanaged.passUnretained(event)
    }
    if InputPoster.isSynthetic(event) {
      if type == .keyDown || type == .keyUp || type == .flagsChanged {
        let eventType =
          switch type {
          case .keyDown: "key_down"
          case .keyUp: "key_up"
          default: "flags_changed"
          }
        logger.write(
          "synthetic_key_observed",
          [
            "event_type": eventType,
            "flags": "\(event.flags.rawValue)",
            "key_code": "\(event.getIntegerValueField(.keyboardEventKeycode))",
          ])
      }
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
    case .keyDown:
      recordObservation(keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
      return Unmanaged.passUnretained(event)
    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func begin(at point: CGPoint, timestamp: UInt64) {
    tracker.begin(at: point)
    previousX = point.x
    scrollStarted = false
    scrollPoster.beginSequence()
    lastGestureID = UUID().uuidString
    fluidStarted = false
    fluidProgressValue = 0
    fluidStartPoint = point
    fluidFullDistanceValue = fluidFullDistance(
      displayWidth: displayWidth(containing: point),
      customDistance: configuration.fluidDistance
    )
    lastFluidPostTimestamp = nil
    fluidProgressLogLimiter.reset()
    fluidMotionTracker.reset(timestamp: timestamp)
    overlay?.show(at: point)
    logger.write("gesture_began", ["gesture_id": lastGestureID!])
  }

  private func drag(to point: CGPoint, timestamp: UInt64) {
    guard let update = tracker.move(to: point), let previousX else { return }
    overlay?.update(update)
    if configuration.mode == .privateDrag {
      updateFluidDrag(update, timestamp: timestamp)
      self.previousX = point.x
      return
    }
    if configuration.mode.postsScroll {
      let phase: CGScrollPhase = scrollStarted ? .changed : .began
      if let fields = scrollPoster.post(deltaX: point.x - previousX, phase: phase) {
        logger.write(
          "scroll_posted", fields.merging(["gesture_id": lastGestureID!]) { current, _ in current })
      }
      scrollStarted = true
    }
    self.previousX = point.x
  }

  private func finish(at point: CGPoint, timestamp: UInt64) {
    if configuration.mode.postsScroll, scrollStarted {
      if let fields = scrollPoster.post(deltaX: 0, phase: .ended) {
        logger.write(
          "scroll_posted", fields.merging(["gesture_id": lastGestureID!]) { current, _ in current })
      }
    }
    let completion = tracker.end(at: point)
    var outcome = completion.outcome
    let releaseDeltaX = Double(completion.update?.deltaX ?? 0)
    overlay?.hide()
    if configuration.mode == .privateDrag {
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
      scrollStarted = false
      return
    }
    switch outcome {
    case .switchSpace(let direction):
      if configuration.mode.sendsShortcut {
        postShortcutAfterMouseRelease(direction: direction, gestureID: lastGestureID!)
      }
      logger.write(
        "gesture_ended", ["gesture_id": lastGestureID!, "outcome": "switch_\(direction.rawValue)"])
      if configuration.mode.postsScroll {
        logger.write(
          "observation_required",
          ["gesture_id": lastGestureID!, "prompt": "press Y if Spaces moved live, N if it did not"])
      }
    case .rightClick:
      InputPoster.rightClick(at: point)
      logger.write("gesture_ended", ["gesture_id": lastGestureID!, "outcome": "right_click"])
    case .none:
      break
    }
    previousX = nil
    scrollStarted = false
  }

  private func updateFluidDrag(
    _ update: GestureUpdate,
    timestamp: UInt64,
    forcePost: Bool = false
  ) {
    guard let location = fluidStartPoint else { return }
    fluidMotionTracker.sample(deltaX: Double(update.deltaX), timestamp: timestamp)
    let activationDistance = min(configuration.threshold, 6)
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
    
    // MMF uses: exitSpeed = _dockSwipeLastDelta * 100
    // We approximate last frame's delta from velocity (points per second) / 60 frames per second
    let lastFrameDeltaX = motion.velocityX / 60.0
    let exitSpeed = lastFrameDeltaX * scaleH * -100.0
    
    // MMF logic: If direction of velocity is opposite to progress, cancel
    // Note: fluidProgressValue is inverted (left drag = positive progress). 
    // velocityX is positive when dragging right.
    // So if velocityX > 0, we are dragging right (progress should be negative).
    // If progress is positive (we dragged left overall), and velocityX > 0 (flicked right), they are opposite.
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

  private func recordObservation(keyCode: CGKeyCode) {
    guard let gestureID = lastGestureID else { return }
    let result = keyCode == 16 ? "live" : keyCode == 45 ? "not_live" : nil
    guard let result else { return }
    logger.write("spaces_live_animation_observation", ["gesture_id": gestureID, "result": result])
  }

  private func postShortcutAfterMouseRelease(
    direction: GestureDirection, gestureID: String
  ) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(50))
      await InputPoster.shortcut(direction: direction)
      logger.write(
        "shortcut_posted",
        [
          "gesture_id": gestureID, "shortcut": "control_\(direction.rawValue)",
        ])
    }
  }
}

enum ControllerError: Error {
  case eventTapUnavailable
}
