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
  private var fluidProgressLogLimiter = TimestampRateLimiter(
    intervalNanoseconds: 100_000_000
  )
  private var fluidMotionTracker = FluidMotionTracker()
  private var settlingTask: Task<Void, Never>?
  private var pendingFluidSettle: PendingFluidSettle?

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
    finalizePendingFluidSettle()
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

    if !fluidStarted {
      _ = fluidPoster.post(phase: .mayBegin, progress: 0, location: location)
      _ = fluidPoster.post(phase: .began, progress: 0, location: location)
      fluidStarted = true
      logger.write(
        "fluid_drag_began",
        [
          "gesture_id": lastGestureID!,
          "full_distance": "\(fluidFullDistanceValue)",
          "commit_distance": "\(fluidFullDistanceValue * 0.5)",
        ])
    }

    fluidProgressValue = fluidProgress(
      deltaX: Double(update.deltaX),
      fullDistance: fluidFullDistanceValue
    )
    if !forcePost,
      let lastFluidPostTimestamp,
      timestamp >= lastFluidPostTimestamp,
      timestamp - lastFluidPostTimestamp < 8_000_000
    {
      return
    }
    lastFluidPostTimestamp = timestamp
    if let fields = fluidPoster.post(
      phase: .changed,
      progress: fluidProgressValue,
      location: location
    ), fluidProgressLogLimiter.shouldEmit(timestamp: timestamp, force: forcePost) {
      logger.write(
        "fluid_drag_progress",
        fields.merging(["gesture_id": lastGestureID!]) { current, _ in current })
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
    let target = fluidReleaseTarget(for: outcome)
    let settleVelocity = fluidSettleVelocity(
      for: outcome,
      releaseVelocityX: motion.velocityX
    )
    let frameCount = fluidSettleFrameCount(velocityX: settleVelocity)
    let progresses = fluidSettleProgresses(
      from: fluidProgressValue,
      to: target,
      frameCount: frameCount,
      velocityX: settleVelocity
    )
    let gestureID = lastGestureID!
    let context = PendingFluidSettle(
      location: location,
      target: target,
      gestureID: gestureID,
      outcome: outcome,
      motion: motion,
      releaseDeltaX: releaseDeltaX
    )
    pendingFluidSettle = context
    settlingTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for progress in progresses {
        guard !Task.isCancelled else { return }
        _ = fluidPoster.post(phase: .changed, progress: progress, location: location)
        try? await Task.sleep(for: .milliseconds(8))
      }
      guard !Task.isCancelled else { return }
      guard pendingFluidSettle?.gestureID == gestureID else { return }
      pendingFluidSettle = nil
      settlingTask = nil
      postFluidSettleEnd(context, interrupted: false)
    }
  }

  private func finalizePendingFluidSettle() {
    settlingTask?.cancel()
    settlingTask = nil
    guard let context = pendingFluidSettle else { return }
    pendingFluidSettle = nil
    postFluidSettleEnd(context, interrupted: true)
  }

  private func postFluidSettleEnd(_ context: PendingFluidSettle, interrupted: Bool) {
    let projectedDeltaX = fluidProjectedDeltaX(
      deltaX: context.releaseDeltaX,
      velocityX: context.motion.velocityX
    )
    let fields = fluidPoster.post(
      phase: .ended,
      progress: context.target,
      location: context.location
    ) ?? [:]
    logger.write(
      "fluid_drag_ended",
      fields.merging(
        [
          "gesture_id": context.gestureID,
          "outcome": context.outcome.logName,
          "release_velocity_x": "\(context.motion.velocityX)",
          "release_delta_x": "\(context.releaseDeltaX)",
          "projected_delta_x": "\(projectedDeltaX)",
          "directional_coherence": "\(context.motion.directionalCoherence)",
          "settle_interrupted": "\(interrupted)",
        ]
      ) { current, _ in current })
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
