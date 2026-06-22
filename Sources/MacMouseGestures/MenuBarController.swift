import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let popover = NSPopover()

  init(settings: AppSettings) {
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

    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 300, height: 270)
    popover.contentViewController = NSHostingController(
      rootView: MenuBarView(settings: settings)
    )
  }

  @objc private func togglePopover(_ sender: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }
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
