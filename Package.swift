// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacMouseGestures",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GestureCore", targets: ["GestureCore"]),
    .executable(name: "MacMouseGestures", targets: ["MacMouseGestures"]),
  ],
  targets: [
    .target(name: "GestureCore"),
    .target(name: "DockSwipeBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
    .executableTarget(
      name: "MacMouseGestures",
      dependencies: ["GestureCore", "DockSwipeBridge"]
    ),
    .testTarget(
      name: "GestureCoreTests",
      dependencies: ["GestureCore", "DockSwipeBridge"]
    ),
  ]
)
