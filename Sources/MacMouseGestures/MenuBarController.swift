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

private final class MenuBarPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

private struct MenuBarView: View {
  @ObservedObject var settings: AppSettings
  let onHideMenuBarIconChange: (Bool) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "computermouse")
          .font(.title2)
        Text("Mac Mouse Gestures")
          .font(.headline)
        Spacer()
        Toggle("Gestures", isOn: $settings.gesturesEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityLabel("Enable Mac Mouse Gestures")
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text("Mouse Buttons")
          .font(.caption)
          .foregroundStyle(.secondary)

        actionRow(
          slotLabel: "First",
          buttonNumber: $settings.mouseButton3Number,
          action: $settings.mouseButton3Action
        )
        actionRow(
          slotLabel: "Second",
          buttonNumber: $settings.mouseButton4Number,
          action: $settings.mouseButton4Action
        )

        Text("Record a mouse button, then choose its action.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Divider()

      HStack {
        Toggle(
          "Hide Menu Bar Icon",
          isOn: Binding(
            get: { settings.hideMenuBarIcon },
            set: {
              settings.hideMenuBarIcon = $0
              onHideMenuBarIconChange($0)
            }
          )
        )
        .toggleStyle(.checkbox)
        .font(.caption)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .accessibilityLabel("Hide menu bar icon")

        Spacer()

        Toggle("Launch at Login", isOn: $settings.launchAtLogin)
          .toggleStyle(.checkbox)
          .font(.caption)
          .foregroundStyle(.secondary)
          .controlSize(.small)
          .accessibilityLabel("Launch at login")

        Spacer()

        Button("Quit", systemImage: "power") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }
    }
    .padding(16)
    .frame(width: 340)
  }

  private func actionRow(
    slotLabel: String,
    buttonNumber: Binding<Int64>,
    action: Binding<MouseButtonAction>
  ) -> some View {
    let mouseLabel = "Mouse \(buttonNumber.wrappedValue)"

    return HStack(spacing: 8) {
      MouseButtonRecorder(
        label: "Record \(slotLabel.lowercased()) mouse button",
        buttonNumber: buttonNumber
      )
      .frame(width: 84, height: 26)

      Picker("\(mouseLabel) action", selection: action) {
        ForEach(MouseButtonAction.allCases) { action in
          Text(action.displayName).tag(action)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 190, alignment: .leading)
      .accessibilityLabel("\(mouseLabel) action")

      Spacer(minLength: 0)
    }
  }
}
