import CoreGraphics

public enum GestureDirection: String, Equatable, Sendable {
  case left
  case right
}

public enum GestureOutcome: Equatable, Sendable {
  case none
  case rightClick
  case switchSpace(GestureDirection)
}

extension GestureOutcome {
  public var logName: String {
    switch self {
    case .none: "none"
    case .rightClick: "right_click"
    case .switchSpace(let direction): "switch_\(direction.rawValue)"
    }
  }
}

public struct GestureUpdate: Equatable, Sendable {
  public let deltaX: CGFloat
  public let progress: CGFloat
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

  public init(threshold: CGFloat = 80) {
    precondition(threshold > 0)
    self.threshold = threshold
  }

  public var isTracking: Bool { origin != nil }

  public mutating func begin(at point: CGPoint) {
    origin = point
    latestUpdate = nil
  }

  public mutating func move(to point: CGPoint) -> GestureUpdate? {
    guard let origin else { return nil }

    let deltaX = point.x - origin.x
    let deltaY = point.y - origin.y
    guard abs(deltaX) > abs(deltaY) else {
      latestUpdate = nil
      return nil
    }

    let update = GestureUpdate(
      deltaX: deltaX,
      progress: min(abs(deltaX) / threshold, 1),
      direction: deltaX < 0 ? .left : .right
    )
    latestUpdate = update
    return update
  }

  public mutating func end() -> GestureOutcome {
    guard origin != nil else { return .none }
    defer {
      origin = nil
      latestUpdate = nil
    }

    guard let latestUpdate, abs(latestUpdate.deltaX) >= threshold else {
      return .rightClick
    }
    return .switchSpace(latestUpdate.direction)
  }

  public mutating func end(at point: CGPoint) -> GestureCompletion {
    let update = move(to: point)
    return GestureCompletion(update: update, outcome: end())
  }
}
