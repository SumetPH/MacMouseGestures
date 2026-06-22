// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacMouseGesture",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GestureCore", targets: ["GestureCore"]),
    .executable(name: "mac-mouse-gesture", targets: ["MacMouseGesture"]),
  ],
  targets: [
    .target(name: "GestureCore"),
    .executableTarget(
      name: "MacMouseGesture",
      dependencies: ["GestureCore"]
    ),
    .testTarget(
      name: "GestureCoreTests",
      dependencies: ["GestureCore"]
    ),
  ]
)
