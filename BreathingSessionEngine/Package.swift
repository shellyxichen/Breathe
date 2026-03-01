// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "BreathingSessionEngine",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "BreathingSessionEngine",
      targets: ["BreathingSessionEngine"]
    ),
  ],
  targets: [
    .target(
      name: "BreathingSessionEngine",
      resources: [
        .process("Resources"),
      ]
    ),
    .testTarget(
      name: "BreathingSessionEngineTests",
      dependencies: ["BreathingSessionEngine"]
    ),
  ]
)

