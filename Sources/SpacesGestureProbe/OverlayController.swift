import AppKit
import GestureCore

@MainActor
final class OverlayController {
  private let panel: NSPanel
  private let label: NSTextField

  init() {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 150, height: 54),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

    label = NSTextField(labelWithString: "Right-drag")
    label.alignment = .center
    label.textColor = .white
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.frame = panel.contentView!.bounds
    label.autoresizingMask = [.width, .height]
    panel.contentView?.addSubview(label)
  }

  func show(at _: CGPoint) {
    let point = NSEvent.mouseLocation
    panel.setFrameOrigin(NSPoint(x: point.x + 18, y: point.y - 70))
    label.stringValue = "Right-drag"
    panel.orderFrontRegardless()
  }

  func update(_ update: GestureUpdate) {
    let arrow = update.direction == .left ? "←" : "→"
    label.stringValue = "\(arrow) \(Int(update.progress * 100))%"
  }

  func hide() {
    panel.orderOut(nil)
  }
}
