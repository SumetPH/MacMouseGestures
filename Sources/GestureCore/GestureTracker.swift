import CoreGraphics

public enum GestureDirection: String, Equatable, Sendable {
  case left
  case right
  case up
  case down
}

public enum GestureAxis: String, Equatable, Sendable {
  case horizontal
  case vertical
}

public enum GestureOutcome: Equatable, Sendable {
  case none
  case rightClick
  case switchSpace(GestureDirection)
  case missionControl(GestureDirection)
}

extension GestureOutcome {
  public var logName: String {
    switch self {
    case .none: "none"
    case .rightClick: "right_click"
    case .switchSpace(let direction): "switch_\(direction.rawValue)"
    case .missionControl(let direction): "mission_control_\(direction.rawValue)"
    }
  }
}

public struct GestureUpdate: Equatable, Sendable {
  public let deltaX: CGFloat
  public let deltaY: CGFloat
  public let progress: CGFloat
  public let axis: GestureAxis
  public let direction: GestureDirection
}

public struct GestureCompletion: Equatable, Sendable {
  public let update: GestureUpdate?
  public let outcome: GestureOutcome
}

public struct GestureTracker: Sendable {
  private let threshold: CGFloat
  private var origin: CGPoint?
  private var latestUpdate: GestureUpdate?
  private var axis: GestureAxis?

  public init(threshold: CGFloat = 80) {
    precondition(threshold > 0)
    self.threshold = threshold
  }

  public var isTracking: Bool { origin != nil }

  public mutating func begin(at point: CGPoint) {
    origin = point
    latestUpdate = nil
    axis = nil
  }

  public mutating func move(to point: CGPoint) -> GestureUpdate? {
    guard let origin else { return nil }

    let deltaX = point.x - origin.x
    let deltaY = point.y - origin.y

    if axis == nil {
      let distance = max(abs(deltaX), abs(deltaY))
      if distance >= 7 {
        axis = abs(deltaX) >= abs(deltaY) ? .horizontal : .vertical
      } else {
        return nil
      }
    }

    guard let lockedAxis = axis else { return nil }

    let direction: GestureDirection
    let progress: CGFloat

    if lockedAxis == .horizontal {
      direction = deltaX < 0 ? .left : .right
      progress = min(abs(deltaX) / threshold, 1)
    } else {
      direction = deltaY < 0 ? .up : .down
      progress = min(abs(deltaY) / threshold, 1)
    }

    let update = GestureUpdate(
      deltaX: deltaX,
      deltaY: deltaY,
      progress: progress,
      axis: lockedAxis,
      direction: direction
    )
    latestUpdate = update
    return update
  }

  public mutating func end() -> GestureOutcome {
    guard origin != nil else { return .none }
    defer {
      origin = nil
      latestUpdate = nil
      axis = nil
    }

    guard let latestUpdate else {
      return .rightClick
    }
    
    let activeDelta = latestUpdate.axis == .horizontal ? latestUpdate.deltaX : latestUpdate.deltaY
    guard abs(activeDelta) >= threshold else {
      return .rightClick
    }
    
    if latestUpdate.axis == .horizontal {
      return .switchSpace(latestUpdate.direction)
    } else {
      return .missionControl(latestUpdate.direction)
    }
  }

  public mutating func end(at point: CGPoint) -> GestureCompletion {
    let update = move(to: point)
    return GestureCompletion(update: update, outcome: end())
  }
}
