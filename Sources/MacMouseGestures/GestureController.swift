import AppKit
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
  private var gesturesEnabled = true
  private var tracker = GestureTracker(threshold: 80.0) // Default threshold
  private var pointerGestureTap: CFMachPort?
  private var lastGestureID: String?
  private var fluidStarted = false
  private var fluidProgressValue = 0.0
  private var fluidDisplayWidth = 1440.0
  private var fluidDisplayHeight = 900.0
  private var scaleH = 0.0
  private var scaleV = 0.0
  private var fluidStartPoint: CGPoint?
  private var lastFluidPostTimestamp: UInt64?
  private var fluidProgressLogLimiter = TimestampRateLimiter(
    intervalNanoseconds: 100_000_000
  )
  private var fluidMotionTracker = FluidMotionTracker()
  private var immediateOutcome: GestureOutcome?
  private var wakeObserver: NotificationObserver?
  private var isMissionControlActiveOnStart = false
  private let volumeModifierButtonNumber: Int64 = 4
  private var isVolumeModifierHeld = false

  init() {}



  func apply(settings: AppSettings.Values) {
    gesturesEnabled = settings.gesturesEnabled
  }

  func start() throws {
    let pointer = Unmanaged.passUnretained(self).toOpaque()

    pointerGestureTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask(for: [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
      ]),
      callback: eventTapCallback,
      userInfo: pointer
    )
    guard let pointerGestureTap,
      let pointerSource = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, pointerGestureTap, 0)
    else {
      throw ControllerError.eventTapUnavailable
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), pointerSource, .commonModes)
    CGEvent.tapEnable(tap: pointerGestureTap, enable: true)

    // Warm up WindowServer caches after screen wakes 
    // to avoid stale CVDisplayLink timestamps causing jitter and first-swipe lag.
    wakeObserver = NotificationObserver { [weak self] in
      self?.warmUpAfterWake()
    }

    logger.write(
      "probe_started",
      [
        "mode": "private-drag",
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "pointer_tap": "session_active",
        "volume_gesture": "button_4_left_right_click",
        "event_mask": "gesture_control",
      ])
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let pointerGestureTap { CGEvent.tapEnable(tap: pointerGestureTap, enable: true) }
      logger.write("event_tap_reenabled", ["reason": "\(type.rawValue)"])
      return Unmanaged.passUnretained(event)
    }
    if InputPoster.isSynthetic(event) {
      return Unmanaged.passUnretained(event)
    }

    switch type {
    case .leftMouseDown:
      guard isVolumeModifierHeld else { return Unmanaged.passUnretained(event) }
      InputPoster.volumeDown()
      logger.write("volume_click", ["direction": "down", "button": "left"])
      return nil
    case .leftMouseUp:
      guard isVolumeModifierHeld else { return Unmanaged.passUnretained(event) }
      return nil
    case .rightMouseDown:
      if isVolumeModifierHeld {
        InputPoster.volumeUp()
        logger.write("volume_click", ["direction": "up", "button": "right"])
        return nil
      }
      guard gesturesEnabled else { return Unmanaged.passUnretained(event) }
      begin(at: event.location, timestamp: event.timestamp)
      return nil
    case .rightMouseDragged:
      guard !isVolumeModifierHeld else { return nil }
      guard gesturesEnabled else { return Unmanaged.passUnretained(event) }
      guard tracker.isTracking else { return Unmanaged.passUnretained(event) }
      drag(to: event.location, timestamp: event.timestamp)
      return nil
    case .rightMouseUp:
      guard !isVolumeModifierHeld else { return nil }
      guard gesturesEnabled else { return Unmanaged.passUnretained(event) }
      guard tracker.isTracking else { return Unmanaged.passUnretained(event) }
      finish(at: event.location, timestamp: event.timestamp)
      return nil
    case .otherMouseDown:
      return handleOtherMouseDown(event)
    case .otherMouseUp:
      return handleOtherMouseUp(event)
    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func handleOtherMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    logger.write("other_mouse_down", ["button_number": "\(buttonNumber)"])

    guard buttonNumber == volumeModifierButtonNumber else {
      return Unmanaged.passUnretained(event)
    }

    isVolumeModifierHeld = true
    logger.write(
      "volume_modifier_began",
      ["button_number": "\(buttonNumber)"])
    return nil
  }

  private func handleOtherMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    logger.write("other_mouse_up", ["button_number": "\(buttonNumber)"])

    guard buttonNumber == volumeModifierButtonNumber else {
      return Unmanaged.passUnretained(event)
    }

    isVolumeModifierHeld = false
    logger.write("volume_modifier_ended", ["button_number": "\(buttonNumber)"])
    return nil
  }

  private func eventMask(for eventTypes: [CGEventType]) -> CGEventMask {
    eventTypes.reduce(CGEventMask(0)) {
      $0 | (CGEventMask(1) << $1.rawValue)
    }
  }

  private func begin(at point: CGPoint, timestamp: UInt64) {
    tracker.begin(at: point)
    lastGestureID = UUID().uuidString
    fluidStarted = false
    fluidProgressValue = 0
    fluidStartPoint = point
    immediateOutcome = nil
    
    isMissionControlActiveOnStart = false
    Task.detached(priority: .userInitiated) { [weak self] in
      let active = self?.isMissionControlActive() ?? false
      await MainActor.run {
        self?.isMissionControlActiveOnStart = active
      }
    }
    
    let bounds = displayBounds(containing: point)
    fluidDisplayWidth = Double(bounds.width)
    fluidDisplayHeight = Double(bounds.height)
    
    scaleH = 2.0 / (fluidDisplayWidth + 63.0)
    scaleV = 1.0 / fluidDisplayHeight
    
    lastFluidPostTimestamp = nil
    fluidProgressLogLimiter.reset()
    fluidMotionTracker.reset(timestamp: timestamp)
    logger.write("gesture_began", ["gesture_id": lastGestureID!])
  }

  private func drag(to point: CGPoint, timestamp: UInt64) {
    guard let update = tracker.move(to: point) else { return }
    guard immediateOutcome == nil else { return }

    if let outcome = update.immediateOutcome {
      immediateOutcome = outcome
      logger.write(
        "gesture_triggered_during_drag",
        ["gesture_id": lastGestureID!, "outcome": outcome.logName])
      if case .missionControl(let direction) = outcome {
        Task {
          await InputPoster.missionControlShortcut(direction: direction)
        }
      }
      return
    }

    guard update.usesFluidPreview else { return }
    updateFluidDrag(update, timestamp: timestamp)
  }

  private func finish(at point: CGPoint, timestamp: UInt64) {
    if let immediateOutcome {
      _ = tracker.end(at: point)
      logger.write(
        "gesture_ended",
        ["gesture_id": lastGestureID!, "outcome": immediateOutcome.logName])
      self.immediateOutcome = nil
      return
    }

    let completion = tracker.end(at: point)
    var outcome = completion.outcome
    let releaseDelta = Double(completion.update?.axis == .horizontal ? (completion.update?.deltaX ?? 0) : (completion.update?.deltaY ?? 0))
    let lockedAxis = completion.update?.axis ?? .horizontal
    
    if let finalUpdate = completion.update {
      updateFluidDrag(finalUpdate, timestamp: timestamp, forcePost: true)
      let motion = fluidMotionTracker.estimate
      let velocityVal = lockedAxis == .horizontal ? motion.velocityX : motion.velocityY
      outcome = fluidReleaseOutcome(
        deltaX: Double(lockedAxis == .horizontal ? finalUpdate.deltaX : finalUpdate.deltaY),
        velocityX: velocityVal,
        directionalCoherence: motion.directionalCoherence,
        fullDistance: lockedAxis == .horizontal ? fluidDisplayWidth * 0.30 : fluidDisplayHeight * 0.30,
        axis: lockedAxis
      )
    }
    finishFluidDrag(
      outcome: outcome,
      axis: lockedAxis,
      releasePoint: point,
      motion: fluidMotionTracker.estimate,
      releaseDelta: releaseDelta
    )
  }

  private func updateFluidDrag(
    _ update: GestureUpdate,
    timestamp: UInt64,
    forcePost: Bool = false
  ) {
    guard let location = fluidStartPoint else { return }
    fluidMotionTracker.sample(deltaX: Double(update.deltaX), deltaY: Double(update.deltaY), timestamp: timestamp)
    
    if !fluidStarted {
      _ = fluidPoster.post(phase: .mayBegin, progress: 0, location: location, axis: update.axis)
      _ = fluidPoster.post(phase: .began, progress: 0, location: location, axis: update.axis)
      fluidStarted = true
      fluidProgressValue = 0
      logger.write(
        "fluid_drag_began",
        [
          "gesture_id": lastGestureID!,
          "axis": update.axis.rawValue,
          "display_width": "\(fluidDisplayWidth)",
          "display_height": "\(fluidDisplayHeight)"
        ])
    }

    if update.axis == .horizontal {
      fluidProgressValue = Double(update.deltaX) * scaleH * -1.0
    } else {
      fluidProgressValue = Double(update.deltaY) * scaleV * -1.0
    }

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
      location: location,
      axis: update.axis
    )
    if posted, fluidProgressLogLimiter.shouldEmit(timestamp: timestamp, force: forcePost) {
      logger.write(
        "fluid_drag_progress",
        ["progress": "\(fluidProgressValue)", "gesture_id": lastGestureID!])
    }
  }

  private func finishFluidDrag(
    outcome: GestureOutcome,
    axis: GestureAxis,
    releasePoint: CGPoint,
    motion: FluidMotionEstimate,
    releaseDelta: Double
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
    
    let exitSpeed: Double
    if axis == .horizontal {
      let lastFrameDeltaX = motion.velocityX / 60.0
      exitSpeed = lastFrameDeltaX * scaleH * -100.0
    } else {
      let lastFrameDeltaY = motion.velocityY / 60.0
      exitSpeed = lastFrameDeltaY * scaleV * -100.0
    }
    
    let velocityVal = axis == .horizontal ? motion.velocityX : motion.velocityY
    let isCancelled: Bool
    if (velocityVal < -50 && fluidProgressValue < 0) || (velocityVal > 50 && fluidProgressValue > 0) {
      isCancelled = true
    } else {
      isCancelled = abs(fluidProgressValue) < 0.5 && abs(velocityVal) < 200
    }
    
    var phase: FluidGesturePhase = isCancelled ? .cancelled : .ended
    let isSwitchSpaceRightInMissionControl = (phase == .ended && isMissionControlActiveOnStart && {
      if case .switchSpace(.left) = outcome { return true }
      return false
    }())

    let postProgress: Double
    if isSwitchSpaceRightInMissionControl {
      phase = .cancelled
      postProgress = fluidProgressValue
    } else if phase == .ended && isMissionControlActiveOnStart {
      postProgress = fluidReleaseTarget(for: outcome)
    } else {
      postProgress = fluidProgressValue
    }
    
    _ = fluidPoster.post(
      phase: phase,
      progress: postProgress,
      velocity: exitSpeed,
      location: location,
      axis: axis,
      doubleSend: !isMissionControlActiveOnStart
    )

    logger.write(
      "fluid_drag_ended",
      [
        "gesture_id": lastGestureID!,
        "outcome": isCancelled ? "cancelled" : "ended",
        "release_velocity": "\(velocityVal)",
        "release_delta": "\(releaseDelta)",
        "exit_speed": "\(exitSpeed)",
        "progress": "\(fluidProgressValue)",
        "is_mc_active": "\(isMissionControlActiveOnStart)"
      ]
    )

    if phase == .ended {
      if case .missionControl(let direction) = outcome {
        Task {
          await InputPoster.missionControlShortcut(direction: direction)
        }
      }
    } else if isSwitchSpaceRightInMissionControl {
      if case .switchSpace(let direction) = outcome {
        Task {
          try? await Task.sleep(for: .milliseconds(100))
          await InputPoster.switchSpaceShortcut(direction: direction)
        }
      }
    }
  }

  private func displayBounds(containing point: CGPoint) -> CGRect {
    var display = CGDirectDisplayID()
    var count: UInt32 = 0
    let result = CGGetDisplaysWithPoint(point, 1, &display, &count)
    guard result == .success, count > 0 else { return CGRect(x: 0, y: 0, width: 1440, height: 900) }
    return CGDisplayBounds(display)
  }

  nonisolated private func isMissionControlActive() -> Bool {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
      if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Dock" {
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        if layer == 18 {
          return true
        }
      }
    }
    return false
  }

  private func warmUpAfterWake() {
    logger.write("warmup_after_wake_began", [:])
    // Query display bounds and window list asynchronously in the background
    // to warm up WindowServer caches before the user initiates a swipe.
    Task.detached(priority: .userInitiated) {
      // 1. Warm up CGWindowListCopyWindowInfo
      _ = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
      
      // 2. Warm up display lookup with CGGetDisplaysWithPoint
      var display = CGDirectDisplayID()
      var count: UInt32 = 0
      _ = CGGetDisplaysWithPoint(.zero, 1, &display, &count)
      
      await MainActor.run { [weak self] in
        self?.logger.write("warmup_after_wake_completed", [:])
      }
    }
  }
}

enum ControllerError: Error {
  case eventTapUnavailable
}

private final class NotificationObserver: NSObject, @unchecked Sendable {
  private let onWake: @MainActor () -> Void

  init(onWake: @escaping @MainActor @Sendable () -> Void) {
    self.onWake = onWake
    super.init()
    
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
    center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  @objc private func handleWake() {
    Task { @MainActor in
      self.onWake()
    }
  }
}
