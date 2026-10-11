import AppKit
import MacMouseGesturesCore
import SwiftUI

final class MenuBarPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

struct MenuBarView: View {
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
