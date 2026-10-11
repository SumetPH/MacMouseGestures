import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let panel: NSPanel
  private let settings: AppSettings
  private var eventMonitors: [Any] = []

  init(settings: AppSettings) {
    self.settings = settings
    let contentSize = NSSize(width: 340, height: 240)
    panel = MenuBarPanel(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )

    super.init()

    statusItem.isVisible = !settings.hideMenuBarIcon

    if let button = statusItem.button {
      let image = NSImage(
        systemSymbolName: "computermouse",
        accessibilityDescription: "Mac Mouse Gestures"
      )
      image?.isTemplate = true
      button.image = image
      button.toolTip = "Mac Mouse Gestures"
      button.target = self
      button.action = #selector(togglePopover(_:))
    }

    panel.level = .popUpMenu
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.collectionBehavior = [.transient, .moveToActiveSpace]
    panel.contentViewController = NSHostingController(
      rootView: MenuBarView(
        settings: settings,
        onHideMenuBarIconChange: { [weak self] hide in
          self?.updateMenuBarIconVisibility(hide)
        }
      )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    )
  }

  func handleApplicationOpen() {
    guard settings.hideMenuBarIcon else { return }

    statusItem.isVisible = true
    showPanelWhenStatusItemIsLaidOut(attemptsLeft: Self.layoutWaitAttempts)
  }

  private static let layoutWaitAttempts = 40
  private static let layoutWaitInterval: TimeInterval = 0.05

  // A freshly shown status item has a zero-height window until the menu bar lays it out.
  private func showPanelWhenStatusItemIsLaidOut(attemptsLeft: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.layoutWaitInterval) { [weak self] in
      guard let self, !self.panel.isVisible, let button = self.statusItem.button else { return }

      let isLaidOut = (button.window?.frame.height ?? 0) > 0 && button.window?.screen != nil
      guard isLaidOut || attemptsLeft <= 0 else {
        self.showPanelWhenStatusItemIsLaidOut(attemptsLeft: attemptsLeft - 1)
        return
      }
      self.showPanel(relativeTo: button)
    }
  }

  @objc private func togglePopover(_ sender: NSStatusBarButton) {
    if panel.isVisible {
      closePanel()
    } else {
      showPanel(relativeTo: sender)
    }
  }

  private func showPanel(relativeTo sender: NSStatusBarButton) {
    guard let buttonWindow = sender.window else { return }

    let buttonFrame = buttonWindow.convertToScreen(sender.convert(sender.bounds, to: nil))
    let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let panelSize = panel.frame.size
    let centeredX = buttonFrame.midX - panelSize.width / 2
    let x = min(max(centeredX, screenFrame.minX), screenFrame.maxX - panelSize.width)

    panel.setFrameOrigin(NSPoint(x: x, y: screenFrame.maxY - panelSize.height))
    panel.orderFrontRegardless()
    panel.makeKey()
    installEventMonitors()

    DispatchQueue.main.async {
      sender.isHighlighted = true
    }
  }

  private func closePanel() {
    DispatchQueue.main.async {
      self.statusItem.button?.isHighlighted = false
    }
    panel.orderOut(nil)
    removeEventMonitors()
    statusItem.isVisible = !settings.hideMenuBarIcon
  }

  private func updateMenuBarIconVisibility(_ hide: Bool) {
    statusItem.isVisible = !hide
  }

  private func installEventMonitors() {
    removeEventMonitors()

    let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: mouseEvents,
      handler: { [weak self] _ in self?.closePanel() }
    ) {
      eventMonitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: mouseEvents,
      handler: { [weak self] event in
        guard event.window !== self?.panel else { return event }
        self?.closePanel()
        return nil
      }
    ) {
      eventMonitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: .keyDown,
      handler: { [weak self] event in
        guard event.keyCode == 53 else { return event }
        self?.closePanel()
        return nil
      }
    ) {
      eventMonitors.append(monitor)
    }
  }

  private func removeEventMonitors() {
    eventMonitors.forEach(NSEvent.removeMonitor)
    eventMonitors.removeAll()
  }
}
