public enum MouseButtonAction: String, CaseIterable, Identifiable, Sendable {
  case none
  case missionControl
  case applicationWindows

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .none: "No Action"
    case .missionControl: "Mission Control"
    case .applicationWindows: "Application Windows"
    }
  }
}
