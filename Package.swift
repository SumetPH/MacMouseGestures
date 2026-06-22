// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SpacesGestureProbe",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GestureCore", targets: ["GestureCore"]),
    .executable(name: "spaces-gesture-probe", targets: ["SpacesGestureProbe"]),
  ],
  targets: [
    .target(name: "GestureCore"),
    .executableTarget(
      name: "SpacesGestureProbe",
      dependencies: ["GestureCore"]
    ),
    .testTarget(
      name: "GestureCoreTests",
      dependencies: ["GestureCore"]
    ),
  ]
)
