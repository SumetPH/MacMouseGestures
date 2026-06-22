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
  private var isEnabled = true
  private var tracker = GestureTracker(threshold: 80.0) // Default threshold
  private var pointerGestureTap: CFMachPort?
  private var scrollTap: CFMachPort?
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
  private lazy var scrollController = ScrollController()
  private var wakeObserver: (any NSObjectProtocol)?

  init() {}



  func apply(settings: AppSettings.Values) {
    isEnabled = settings.isEnabled
    scrollController.setEnabled(settings.isEnabled)
    scrollController.updateConfiguration(
      speed: settings.scrollSpeed,
      smoothness: settings.scrollSmoothness
    )
  }

  func start() throws {
    let pointer = Unmanaged.passUnretained(self).toOpaque()

    pointerGestureTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask(for: [
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
      ]),
      callback: eventTapCallback,
      userInfo: pointer
    )
    scrollTap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask(for: [.scrollWheel]),
      callback: eventTapCallback,
      userInfo: pointer
    )
    guard let pointerGestureTap,
      let scrollTap,
      let pointerSource = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, pointerGestureTap, 0),
      let scrollSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, scrollTap, 0)
    else {
      throw ControllerError.eventTapUnavailable
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), pointerSource, .commonModes)
    CFRunLoopAddSource(CFRunLoopGetMain(), scrollSource, .commonModes)
    CGEvent.tapEnable(tap: pointerGestureTap, enable: true)
    CGEvent.tapEnable(tap: scrollTap, enable: true)

    // Reset scroll animation state after screen wakes to avoid stale
    // CVDisplayLink timestamps causing jitter on first scroll/swipe.
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.scrollController.resetForWake()
      }
    }

    logger.write(
      "probe_started",
      [
        "mode": "private-drag",
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "pointer_tap": "session_active",
        "scroll_tap": "hid_active",
        "event_mask": "gesture_control",
      ])
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let pointerGestureTap { CGEvent.tapEnable(tap: pointerGestureTap, enable: true) }
      if let scrollTap { CGEvent.tapEnable(tap: scrollTap, enable: true) }
      logger.write("event_tap_reenabled", ["reason": "\(type.rawValue)"])
      return Unmanaged.passUnretained(event)
    }
    guard isEnabled else { return Unmanaged.passUnretained(event) }
    if InputPoster.isSynthetic(event) {
      return Unmanaged.passUnretained(event)
    }

    switch type {
    case .scrollWheel:
      return scrollController.handle(event: event)
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
    let isSwitchSpaceRightInMissionControl = (phase == .ended && isMissionControlActive() && {
      if case .switchSpace(.left) = outcome { return true }
      return false
    }())

    let postProgress: Double
    if isSwitchSpaceRightInMissionControl {
      phase = .cancelled
      postProgress = fluidProgressValue
    } else if phase == .ended && isMissionControlActive() {
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
      doubleSend: !isMissionControlActive()
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
        "is_mc_active": "\(isMissionControlActive())"
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

  private func isMissionControlActive() -> Bool {
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
}

enum ControllerError: Error {
  case eventTapUnavailable
}
