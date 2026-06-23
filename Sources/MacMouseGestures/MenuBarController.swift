import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let panel: NSPanel
  private var eventMonitors: [Any] = []

  init(settings: AppSettings) {
    let contentSize = NSSize(width: 300, height: 300)
    panel = MenuBarPanel(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )

    super.init()

    if let button = statusItem.button {
      let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
      let image = NSImage(
        systemSymbolName: "computermouse",
        accessibilityDescription: "Mac Mouse Gestures"
      )?.withSymbolConfiguration(config)
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
      rootView: MenuBarView(settings: settings)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    )
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
  }

  private func closePanel() {
    panel.orderOut(nil)
    removeEventMonitors()
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

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "computermouse")
          .font(.title2)
        Text("Mac Mouse Gestures")
          .font(.headline)
        Spacer()
        Toggle("Enabled", isOn: $settings.isEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityLabel("Enable Mac Mouse Gestures")
      }

      HStack {
        Text("Launch at Login")
        Spacer()
        Toggle("Launch at Login", isOn: $settings.launchAtLogin)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityLabel("Launch at login")
      }

      Divider()

      Text("Scrolling")
        .font(.subheadline.weight(.semibold))

      settingSlider(
        title: "Speed",
        value: $settings.scrollSpeed,
        range: AppSettings.scrollSpeedRange,
        accessibilityLabel: "Scroll speed"
      )
      settingSlider(
        title: "Smoothness",
        value: $settings.scrollSmoothness,
        range: AppSettings.scrollSmoothnessRange,
        accessibilityLabel: "Scroll smoothness"
      )

      HStack {
        Button("Reset", systemImage: "arrow.counterclockwise") {
          settings.resetScrolling()
        }
        Spacer()
        Button("Quit", systemImage: "power") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 300)
  }

  private func settingSlider(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    accessibilityLabel: String
  ) -> some View {
    VStack(spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range, step: 0.05)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
          Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
        )
    }
  }
}
