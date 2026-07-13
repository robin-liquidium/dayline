// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "Dayline",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .executable(name: "Dayline", targets: ["Dayline"])
  ],
  targets: [
    .executableTarget(
      name: "Dayline",
      path: "Sources/Dayline"
    ),
    .testTarget(
      name: "DaylineTests",
      dependencies: ["Dayline"],
      path: "Tests/DaylineTests"
    )
  ]
)
