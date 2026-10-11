// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacMouseGestures",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "MacMouseGestures", targets: ["MacMouseGestures"]),
  ],
  targets: [
    .target(name: "MacMouseGesturesCore"),
    .target(name: "MacMouseGesturesBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
    .executableTarget(
      name: "MacMouseGestures",
      dependencies: ["MacMouseGesturesCore", "MacMouseGesturesBridge"]
    ),
    .testTarget(
      name: "MacMouseGesturesCoreTests",
      dependencies: ["MacMouseGesturesCore", "MacMouseGesturesBridge"]
    ),
  ]
)
