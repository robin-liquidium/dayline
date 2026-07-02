// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "StatusWidget",
  platforms: [
    .macOS("27.0")
  ],
  products: [
    .executable(name: "StatusWidget", targets: ["StatusWidget"])
  ],
  targets: [
    .executableTarget(
      name: "StatusWidget",
      path: "Sources/StatusWidget"
    )
  ]
)
