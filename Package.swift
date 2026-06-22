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
    .target(
      name: "CTouchEvents",
      path: "Vendor/TouchEvents",
      exclude: ["LICENSE.md"],
      sources: ["TouchEvents.c"],
      publicHeadersPath: "."
    ),
    .executableTarget(
      name: "SpacesGestureProbe",
      dependencies: ["GestureCore", "CTouchEvents"]
    ),
    .testTarget(
      name: "GestureCoreTests",
      dependencies: ["GestureCore"]
    ),
  ]
)
