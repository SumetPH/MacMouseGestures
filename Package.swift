// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacMouseGestures",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GestureCore", targets: ["GestureCore"]),
    .executable(name: "mac-mouse-gestures", targets: ["MacMouseGestures"]),
  ],
  targets: [
    .target(name: "GestureCore"),
    .executableTarget(
      name: "MacMouseGestures",
      dependencies: ["GestureCore"]
    ),
    .testTarget(
      name: "GestureCoreTests",
      dependencies: ["GestureCore"]
    ),
  ]
)
