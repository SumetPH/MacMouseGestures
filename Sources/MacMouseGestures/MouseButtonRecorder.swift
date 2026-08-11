import AppKit
@preconcurrency import CoreGraphics
import SwiftUI

private func mouseButtonRecorderEventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let recorder = Unmanaged<MouseButtonRecorderButton>.fromOpaque(userInfo)
    .takeUnretainedValue()
  return MainActor.assumeIsolated {
    recorder.handleCapturedEvent(type: type, event: event)
  }
}

struct MouseButtonRecorder: NSViewRepresentable {
  let label: String
  @Binding var buttonNumber: Int64

  func makeNSView(context: Context) -> MouseButtonRecorderButton {
    let button = MouseButtonRecorderButton()
    button.setAccessibilityLabel(label)
    button.onChange = { buttonNumber = $0 }
    return button
  }

  func updateNSView(_ button: MouseButtonRecorderButton, context: Context) {
    button.setAccessibilityLabel(label)
    button.buttonNumber = buttonNumber
    button.onChange = { buttonNumber = $0 }
  }
}

@MainActor
final class MouseButtonRecorderButton: NSButton {
  var buttonNumber: Int64 = 2 {
    didSet { updateTitle() }
  }
  var onChange: (Int64) -> Void = { _ in }

  private var isRecording = false {
    didSet { updateTitle() }
  }
  private var mouseEventTap: CFMachPort?
  private var mouseEventTapSource: CFRunLoopSource?
  private var capturedButtonNumber: Int64?

  override var acceptsFirstResponder: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 84, height: 26) }

  init() {
    super.init(frame: .zero)
    bezelStyle = .rounded
    controlSize = .small
    font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    target = self
    action = #selector(beginRecording)
    updateTitle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func beginRecording() {
    guard window?.makeFirstResponder(self) == true, startMouseCapture() else {
      window?.makeFirstResponder(nil)
      NSSound.beep()
      return
    }
    isRecording = true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    if event.keyCode == 53 {
      finishRecording()
    } else {
      NSSound.beep()
    }
  }

  override func resignFirstResponder() -> Bool {
    let didResign = super.resignFirstResponder()
    if didResign, isRecording {
      finishRecording(clearFirstResponder: false)
    }
    return didResign
  }

  func handleCapturedEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let mouseEventTap {
        CGEvent.tapEnable(tap: mouseEventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard isRecording else {
      return Unmanaged.passUnretained(event)
    }

    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    switch type {
    case .otherMouseDown:
      guard capturedButtonNumber == nil else { return nil }
      capturedButtonNumber = buttonNumber
      self.buttonNumber = buttonNumber
      onChange(buttonNumber)
      return nil

    case .otherMouseUp:
      if buttonNumber == capturedButtonNumber {
        finishRecording()
      }
      return nil

    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func startMouseCapture() -> Bool {
    stopMouseCapture()

    let eventMask =
      (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
      | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: mouseButtonRecorderEventTapCallback,
      userInfo: pointer
    ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else {
      return false
    }

    mouseEventTap = eventTap
    mouseEventTapSource = source
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification,
      object: window
    )
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  private func stopMouseCapture() {
    NotificationCenter.default.removeObserver(
      self,
      name: NSWindow.didResignKeyNotification,
      object: nil
    )
    if let mouseEventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseEventTapSource, .commonModes)
    }
    if let mouseEventTap {
      CFMachPortInvalidate(mouseEventTap)
    }
    mouseEventTapSource = nil
    mouseEventTap = nil
  }

  @objc private func windowDidResignKey(_ notification: Notification) {
    if isRecording {
      finishRecording(clearFirstResponder: false)
    }
  }

  private func finishRecording(clearFirstResponder: Bool = true) {
    isRecording = false
    capturedButtonNumber = nil
    stopMouseCapture()
    if clearFirstResponder {
      window?.makeFirstResponder(nil)
    }
  }

  private func updateTitle() {
    title = isRecording ? "Press mouse…" : "Mouse \(buttonNumber)"
    setAccessibilityValue(isRecording ? "Recording" : "Mouse \(buttonNumber)")
  }
}
