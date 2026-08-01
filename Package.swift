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
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    .package(url: "https://github.com/nodes-app/swift-markdown-engine", exact: "0.11.0")
  ],
  targets: [
    .executableTarget(
      name: "Dayline",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "MarkdownEngine", package: "swift-markdown-engine")
      ],
      path: "Sources/Dayline",
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-rpath",
          "-Xlinker", "@executable_path/../Frameworks"
        ])
      ]
    ),
    .testTarget(
      name: "DaylineTests",
      dependencies: [
        "Dayline",
        .product(name: "MarkdownEngine", package: "swift-markdown-engine")
      ],
      path: "Tests/DaylineTests",
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-rpath",
          "-Xlinker", "@loader_path/../../.."
        ])
      ]
    )
  ]
)
