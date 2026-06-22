import Testing

@testable import GestureCore

@Suite("Native capture safety")
struct CapturePolicyTests {
  @Test("private gesture events remain CoreGraphics-only")
  func privateGestureAvoidsAppKitDecoding() {
    #expect(capturePolicy(forEventType: 29) == .coreGraphicsOnly)
  }

  @Test("scroll events use safe CoreGraphics scroll fields")
  func scrollUsesCoreGraphicsFields() {
    #expect(capturePolicy(forEventType: 22) == .coreGraphicsScrollFields)
  }

  @Test("ordinary mouse events do not need full capture")
  func mouseMoveIsEnvelopeOnly() {
    #expect(capturePolicy(forEventType: 5) == .envelopeOnly)
  }
}
