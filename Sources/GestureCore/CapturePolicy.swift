public enum CapturePolicy: Equatable, Sendable {
  case envelopeOnly
  case coreGraphicsOnly
  case coreGraphicsScrollFields
}

public func capturePolicy(forEventType type: UInt32) -> CapturePolicy {
  if type == 22 {
    return .coreGraphicsScrollFields
  }
  if (28..<64).contains(type) {
    return .coreGraphicsOnly
  }
  return .envelopeOnly
}
