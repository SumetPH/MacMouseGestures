import CoreGraphics
import Foundation
import GestureCore

public final class FluidGestureEventPoster: @unchecked Sendable {
  private let eventSource: CGEventSource?
  private var doubleSendWorkItem: DispatchWorkItem?
  private var tripleSendWorkItem: DispatchWorkItem?

  public init() {
    self.eventSource = CGEventSource(stateID: .hidSystemState)
  }

  @MainActor
  public func post(
    phase: FluidGesturePhase,
    progress: Double,
    velocity: Double = 0.0,
    location: CGPoint
  ) -> Bool {
    // MayBegin is not sent for DockSwipe gestures in Mac Mouse Fix.
    guard phase != .mayBegin else { return true }

    let rawPhase: Int64
    switch phase {
    case .mayBegin: rawPhase = 128
    case .began: rawPhase = 1
    case .changed: rawPhase = 2
    case .ended: rawPhase = 4
    case .cancelled: rawPhase = 8
    }

    if phase == .began {
      doubleSendWorkItem?.cancel()
      tripleSendWorkItem?.cancel()
      doubleSendWorkItem = nil
      tripleSendWorkItem = nil
    }

    let valFor41 = 33231.0
    
    // Create e29 (NSEventTypeGesture) event
    guard let e29 = CGEvent(source: nil) else { return false }
    e29.setDoubleValueField(CGEventField(rawValue: 55)!, value: 29.0) // Set event type
    e29.setDoubleValueField(CGEventField(rawValue: 41)!, value: valFor41)

    // Create e30 event
    guard let e30 = CGEvent(source: nil) else { return false }
    
    e30.setDoubleValueField(CGEventField(rawValue: 55)!, value: 30.0) // Set event type
    e30.setDoubleValueField(CGEventField(rawValue: 110)!, value: 23.0) // subtype = kIOHIDEventTypeDockSwipe (23)
    e30.setDoubleValueField(CGEventField(rawValue: 132)!, value: Double(rawPhase))
    e30.setDoubleValueField(CGEventField(rawValue: 134)!, value: Double(rawPhase))

    e30.setDoubleValueField(CGEventField(rawValue: 124)!, value: progress)
    
    // Encoded Float32 ofs inside Int64
    let floatBits = Float32(progress).bitPattern
    let progressInt64 = Int64(floatBits)
    e30.setIntegerValueField(CGEventField(rawValue: 135)!, value: progressInt64)
    
    e30.setDoubleValueField(CGEventField(rawValue: 41)!, value: valFor41)
    
    // weirdTypeOrSum for horizontal is 1.401298464324817e-45
    let weirdTypeOrSum = 1.401298464324817e-45
    e30.setDoubleValueField(CGEventField(rawValue: 119)!, value: weirdTypeOrSum)
    e30.setDoubleValueField(CGEventField(rawValue: 139)!, value: weirdTypeOrSum)

    e30.setDoubleValueField(CGEventField(rawValue: 123)!, value: 1.0) // Horizontal type = 1
    e30.setDoubleValueField(CGEventField(rawValue: 165)!, value: 1.0)
    
    e30.setIntegerValueField(CGEventField(rawValue: 136)!, value: 0) // invertedFromDevice = false

    if phase == .ended || phase == .cancelled {
      e30.setDoubleValueField(CGEventField(rawValue: 129)!, value: velocity)
      e30.setDoubleValueField(CGEventField(rawValue: 130)!, value: velocity)
    }

    e30.post(tap: .cgSessionEventTap)
    e29.post(tap: .cgSessionEventTap)

    if phase == .ended || phase == .cancelled {
      scheduleDoubleSend(e30: e30, e29: e29)
    }

    return true
  }

  @MainActor
  private func scheduleDoubleSend(e30: CGEvent, e29: CGEvent) {
    guard let copyE30 = e30.copy(), let copyE29 = e29.copy() else { return }

    let doubleItem = DispatchWorkItem {
      copyE30.post(tap: .cgSessionEventTap)
      copyE29.post(tap: .cgSessionEventTap)
    }
    doubleSendWorkItem = doubleItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: doubleItem)

    let tripleItem = DispatchWorkItem {
      copyE30.post(tap: .cgSessionEventTap)
      copyE29.post(tap: .cgSessionEventTap)
    }
    tripleSendWorkItem = tripleItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: tripleItem)
  }
}
