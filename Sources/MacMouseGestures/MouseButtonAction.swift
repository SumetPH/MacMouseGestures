enum MouseButtonAction: String, CaseIterable, Identifiable, Sendable {
  case none
  case missionControl
  case applicationWindows

  var id: Self { self }

  var displayName: String {
    switch self {
    case .none: "No Action"
    case .missionControl: "Mission Control"
    case .applicationWindows: "Application Windows"
    }
  }
}
