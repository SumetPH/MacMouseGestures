import CoreGraphics
import Foundation
import GestureCore

final class ScrollController: @unchecked Sendable {
  private let lock = NSLock()
  private lazy var displayLink = SwiftDisplayLink { [weak self] timing in
    self?.tick(timing: timing)
  }
  
  // State for ScrollAnalyzer
  private var previousScrollTickTimeStamp: Double = 0
  private var previousDirection: ScrollDirection = .none
  private var consecutiveScrollTickCounter: Int = 0
  private var consecutiveScrollSwipeCounter: Double = 0
  private var ticksInCurrentConsecutiveSwipeSequence: Int = 0
  private var consecutiveSwipeSequenceStartTime: Double = -1
  private var tickTimeSmoother = RollingAverage(capacity: 3)
  
  // State for Animator
  private var isRunning = false
  private var animationStartTime: Double = 0
  private var totalDuration: Double = 0
  private var curveDuration: Double = 0
  private var animationValueTotal: Double = 0
  private var lastAnimationValue: Double = 0
  private var lastFrameTime: Double = 0
  private var isWaitingForFirstFrame = false
  private var needsDurationAlignment = false
  private var pixelQuantizerX = BiasedDeltaQuantizer()
  private var pixelQuantizerY = BiasedDeltaQuantizer()
  private var lineQuantizerX = BiasedDeltaQuantizer()
  private var lineQuantizerY = BiasedDeltaQuantizer()
  private var currentDisplayScale = 1.0
  private var speedMultiplier = 1.0
  private var smoothnessMultiplier = 1.0
  
  // Hybrid curve parameters
  private var transitionTime: Double = 0
  private var transitionDistance: Double = 0
  private var v0: Double = 0
  private var isLinearOnly = false
  
  // Direction of current animation
  private var animDirection: ScrollDirection = .none
  
  enum ScrollDirection: Int, Equatable, Sendable {
    case none = 0
    case up = 1
    case down = 2
    case left = 3
    case right = 4
  }

  func updateConfiguration(speed: Double, smoothness: Double) {
    speedMultiplier = speed
    smoothnessMultiplier = smoothness
  }

  func setEnabled(_ enabled: Bool) {
    if !enabled {
      stopAnimation()
    }
  }
  
  func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
    // 1. Filter out synthetic events to prevent infinite loop
    if InputPoster.isSynthetic(event) {
      return Unmanaged.passUnretained(event)
    }
    
    // 2. Filter out continuous (pixel-based) scroll events
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
    let drawingTabletID = event.getIntegerValueField(.tabletEventDeviceID)
    
    // Filter out diagonal scrolls
    let scrollDeltaAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let scrollDeltaAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let isDiagonal = scrollDeltaAxis1 != 0 && scrollDeltaAxis2 != 0
    
    if isContinuous || scrollPhase != 0 || drawingTabletID != 0 || isDiagonal {
      return Unmanaged.passUnretained(event)
    }
    
    let rawDirection: ScrollDirection
    if scrollDeltaAxis1 != 0 {
      rawDirection = scrollDeltaAxis1 > 0 ? .up : .down
    } else if scrollDeltaAxis2 != 0 {
      rawDirection = scrollDeltaAxis2 > 0 ? .right : .left
    } else {
      return Unmanaged.passUnretained(event)
    }
    
    let ts = Double(event.timestamp) / 1_000_000_000.0
    
    lock.lock()
    let analysis = updateAnalyzer(timestamp: ts, direction: rawDirection)
    let running = isRunning
    lock.unlock()

    let startsNewSwipeSequence = analysis.consecutiveScrollTickCounter == 0
      && analysis.consecutiveScrollSwipeCounter == 0
    if startsNewSwipeSequence,
      let displayContext = displayContext(at: event.location, direction: rawDirection)
    {
      currentDisplayScale = displayContext.scale
      if !running {
        displayLink.setCurrentDisplay(displayContext.id)
      }
    }
    
    // 5. Calculate pxToScrollForThisTick
    let consecutiveIntervalMax = 0.16
    let accelerationEnd = 0.015
    
    var timeBetweenTicks = analysis.timeBetweenTicks
    if timeBetweenTicks < 0 {
      timeBetweenTicks = consecutiveIntervalMax
    }
    let animationTickInterval = timeBetweenTicks
    let accelerationTickInterval = max(timeBetweenTicks, accelerationEnd)
    
    let scrollSpeed = 1.0 / accelerationTickInterval
    var pxToScroll = regularMediumPixelsPerTick(
      scrollSpeed: scrollSpeed,
      displayScale: currentDisplayScale,
      speedMultiplier: speedMultiplier
    )
    
    // Apply fast scroll speedup
    let swipeNumber = analysis.consecutiveScrollSwipeCounter + 1.0
    var speedupFactor = 1.0
    if swipeNumber >= 3.0 {
      let b = 1.1
      let c = 7.5
      let p = 1.33
      let a = (p - 1.0) / (pow(b, c) - 1.0)
      speedupFactor = min(a * pow(b, (swipeNumber - 3.0) * c) + (1.0 - a), 100_000)
    }
    pxToScroll *= speedupFactor
    if analysis.scrollDirectionDidChange && running {
      stopAnimation()
    }

    if startsNewSwipeSequence {
      lock.lock()
      pixelQuantizerX.reset()
      pixelQuantizerY.reset()
      lineQuantizerX.reset()
      lineQuantizerY.reset()
      lock.unlock()
    }
    
    lock.lock()
    let activeDeltaLeft = isRunning && !startsNewSwipeSequence
      ? (animationValueTotal - lastAnimationValue)
      : 0.0
    let targetDelta = pxToScroll + activeDeltaLeft
    lock.unlock()
    
    startAnimation(
      delta: targetDelta,
      direction: rawDirection,
      timeBetweenTicks: animationTickInterval
    )
    
    return nil
  }
  
  private struct ScrollAnalysis {
    let consecutiveScrollTickCounter: Int
    let consecutiveScrollSwipeCounter: Double
    let scrollDirectionDidChange: Bool
    let timeBetweenTicks: Double
  }
  
  private func updateAnalyzer(timestamp: Double, direction: ScrollDirection) -> ScrollAnalysis {
    var scrollDirectionDidChange = false
    if previousDirection != direction {
      scrollDirectionDidChange = true
      resetAnalyzer()
    }
    previousDirection = direction
    
    if scrollDirectionDidChange {
      previousScrollTickTimeStamp = timestamp
      return ScrollAnalysis(
        consecutiveScrollTickCounter: 0,
        consecutiveScrollSwipeCounter: 0,
        scrollDirectionDidChange: true,
        timeBetweenTicks: -1.0
      )
    }
    
    let secondsSinceLastTick = max(timestamp - previousScrollTickTimeStamp, 0.001)
    ticksInCurrentConsecutiveSwipeSequence += 1
    
    let consecutiveIntervalMax = 0.16
    let consecutiveSwipeMaxInterval = 0.375
    let consecutiveSwipeMinTickSpeed = 16.0
    let scrollSwipeThresholdInTicks = 2
    
    var smoothedTimeBetweenTicks = -1.0
    
    if secondsSinceLastTick > consecutiveIntervalMax {
      // First consecutive tick of a burst -> Update swipes
      if consecutiveScrollTickCounter >= scrollSwipeThresholdInTicks {
        let interval = secondsSinceLastTick
        if interval <= consecutiveSwipeMaxInterval {
          let nowTime = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
          let duration = nowTime - consecutiveSwipeSequenceStartTime
          let tickSpeed = duration > 0 ? (Double(ticksInCurrentConsecutiveSwipeSequence) / duration) : 0.0
          if tickSpeed >= consecutiveSwipeMinTickSpeed {
            consecutiveScrollSwipeCounter += 1.0
          } else {
            resetSwipes()
          }
        } else {
          resetSwipes()
        }
      } else {
        resetSwipes()
      }
      
      consecutiveScrollTickCounter = 0
      tickTimeSmoother.reset()
      smoothedTimeBetweenTicks = -1.0
    } else {
      // Consecutive tick
      consecutiveScrollTickCounter += 1
      smoothedTimeBetweenTicks = tickTimeSmoother.smooth(value: secondsSinceLastTick)
    }
    
    previousScrollTickTimeStamp = timestamp
    
    return ScrollAnalysis(
      consecutiveScrollTickCounter: consecutiveScrollTickCounter,
      consecutiveScrollSwipeCounter: consecutiveScrollSwipeCounter,
      scrollDirectionDidChange: scrollDirectionDidChange,
      timeBetweenTicks: smoothedTimeBetweenTicks
    )
  }
  
  private func resetAnalyzer() {
    previousScrollTickTimeStamp = 0
    previousDirection = .none
    consecutiveScrollTickCounter = 0
    consecutiveScrollSwipeCounter = 0
    ticksInCurrentConsecutiveSwipeSequence = 0
    consecutiveSwipeSequenceStartTime = -1
  }
  
  private func resetSwipes() {
    consecutiveScrollSwipeCounter = 0
    consecutiveSwipeSequenceStartTime = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    ticksInCurrentConsecutiveSwipeSequence = 0
  }
  
  private func startAnimation(delta: Double, direction: ScrollDirection, timeBetweenTicks: Double) {
    lock.lock()
    defer { lock.unlock() }

    let wasRunning = isRunning
    
    let baseDuration = regularScrollBaseDuration(
      timeBetweenTicks: timeBetweenTicks,
      smoothnessMultiplier: smoothnessMultiplier
    )
    
    self.animDirection = direction
    self.animationValueTotal = delta
    self.lastAnimationValue = 0.0
    
    let dragCoefficient = 23.0
    let stopSpeed = 30.0
    
    self.v0 = delta / baseDuration
    
    if v0 <= stopSpeed {
      self.isLinearOnly = true
      self.totalDuration = baseDuration
    } else {
      self.isLinearOnly = false
      let calculatedDragDistance = (v0 - stopSpeed) / dragCoefficient
      let calculatedTransitionDistance = delta - calculatedDragDistance
      
      if calculatedTransitionDistance < 0 {
        self.transitionDistance = 0.0
        self.transitionTime = 0.0
        self.v0 = delta * dragCoefficient + stopSpeed
        self.totalDuration = log(self.v0 / stopSpeed) / dragCoefficient
      } else {
        self.transitionDistance = calculatedTransitionDistance
        self.transitionTime = self.transitionDistance / v0
        let dragDuration = log(v0 / stopSpeed) / dragCoefficient
        self.totalDuration = self.transitionTime + dragDuration
      }
    }
    self.totalDuration = min(self.totalDuration, 1.5)
    curveDuration = totalDuration

    if wasRunning, lastFrameTime > 0 {
      animationStartTime = lastFrameTime
      isWaitingForFirstFrame = false
    } else {
      animationStartTime = 0
      isWaitingForFirstFrame = true
    }
    needsDurationAlignment = true
    self.isRunning = true
    
    displayLink.start()
  }

  private struct ScrollDisplayContext {
    let id: CGDirectDisplayID
    let scale: Double
  }

  private func displayContext(
    at point: CGPoint,
    direction: ScrollDirection
  ) -> ScrollDisplayContext? {
    var display = CGDirectDisplayID()
    var displayCount: UInt32 = 0
    guard CGGetDisplaysWithPoint(point, 1, &display, &displayCount) == .success,
      displayCount > 0
    else { return nil }

    let scale: Double
    switch direction {
    case .up, .down:
      scale = Double(CGDisplayPixelsHigh(display)) / 1_080.0
    case .left, .right:
      scale = Double(CGDisplayPixelsWide(display)) / 1_920.0
    case .none:
      scale = 1
    }
    return ScrollDisplayContext(id: display, scale: scale)
  }
  
  private func stopAnimation() {
    lock.lock()
    let wasRunning = isRunning
    isRunning = false
    lock.unlock()
    if wasRunning {
      displayLink.stop()
    }
  }
  
  private func tick(timing: DisplayFrameTiming) {
    lock.lock()
    guard isRunning else {
      lock.unlock()
      return
    }
    
    if isWaitingForFirstFrame {
      animationStartTime = timing.outputTime - timing.nominalFrameDuration
      isWaitingForFirstFrame = false
    }
    if needsDurationAlignment {
      totalDuration = scrollDurationAlignedToFrames(
        totalDuration,
        frameDuration: timing.nominalFrameDuration
      )
      needsDurationAlignment = false
    }
    let t = timing.outputTime - animationStartTime
    lastFrameTime = timing.outputTime
    
    var progress: Double = 0.0
    
    if t >= totalDuration {
      progress = 1.0
      isRunning = false
      let displayLink = displayLink
      DispatchQueue.main.async {
        displayLink.stop()
      }
    } else if isLinearOnly {
      progress = t / totalDuration
    } else {
      let curveTime = t * curveDuration / totalDuration
      if curveTime <= transitionTime {
        progress = (v0 * curveTime) / animationValueTotal
      } else {
        let dragTime = curveTime - transitionTime
        let dragCoefficient = 23.0
        let dragDistance = (v0 / dragCoefficient)
          * (1.0 - exp(-dragCoefficient * dragTime))
        progress = (transitionDistance + dragDistance) / animationValueTotal
      }
    }
    
    progress = max(0.0, min(1.0, progress))
    
    let currentValue = progress * animationValueTotal
    let floatDelta = currentValue - lastAnimationValue
    lastAnimationValue = currentValue
    
    let currentDirection = animDirection

    var dxToPost = 0
    var dyToPost = 0
    
    if floatDelta != 0 {
      switch currentDirection {
      case .up:
        dyToPost = pixelQuantizerY.quantize(floatDelta)
      case .down:
        dyToPost = pixelQuantizerY.quantize(-floatDelta)
      case .left:
        dxToPost = pixelQuantizerX.quantize(-floatDelta)
      case .right:
        dxToPost = pixelQuantizerX.quantize(floatDelta)
      case .none:
        break
      }
    }
    
    var dyLineInt = 0
    var dyLineFixed: Int64 = 0
    var dxLineInt = 0
    var dxLineFixed: Int64 = 0
    
    if dyToPost != 0 {
      dyLineInt = lineQuantizerY.quantize(Double(dyToPost) / 10.0)
      dyLineFixed = Int64(dyLineInt) * 65_536
    }
    
    if dxToPost != 0 {
      dxLineInt = lineQuantizerX.quantize(Double(dxToPost) / 10.0)
      dxLineFixed = Int64(dxLineInt) * 65_536
    }
    
    lock.unlock()
    
    // Post events outside the lock
    if dxToPost != 0 || dyToPost != 0 {
      InputPoster.postScrollEvent(
        dx: dxToPost,
        dy: dyToPost,
        dxLineInt: dxLineInt,
        dyLineInt: dyLineInt,
        dxLineFixed: dxLineFixed,
        dyLineFixed: dyLineFixed
      )
    }
  }
}

private struct RollingAverage {
  let capacity: Int
  private var values: [Double] = []

  init(capacity: Int) {
    self.capacity = capacity
  }

  mutating func reset() {
    values.removeAll()
  }

  mutating func smooth(value: Double) -> Double {
    values.append(value)
    if values.count > capacity {
      values.removeFirst()
    }
    return values.reduce(0, +) / Double(values.count)
  }
}
