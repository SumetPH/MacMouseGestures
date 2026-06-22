import Foundation

/// Converts fractional animation deltas to integer event deltas while carrying
/// rounding error across frames. The first non-zero frame is biased away from
/// zero, matching the subpixelator used by Mac Mouse Fix.
public struct BiasedDeltaQuantizer: Sendable {
  private var accumulatedError = 0.0
  private var direction: FloatingPointSign?

  public init() {}

  public mutating func reset() {
    accumulatedError = 0
    direction = nil
  }

  public mutating func quantize(_ delta: Double) -> Int {
    guard delta != 0 else { return 0 }

    if direction == nil {
      direction = delta.sign
    }

    let preciseDelta = delta + accumulatedError
    let output: Double
    if direction == .minus {
      output = floor(preciseDelta)
    } else {
      output = ceil(preciseDelta)
    }
    accumulatedError = preciseDelta - output
    return Int(output)
  }
}
