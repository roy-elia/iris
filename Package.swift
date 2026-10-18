// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "FileDropUtility",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "FileDropUtility", targets: ["FileDropUtility"]),
    .library(name: "DropCore", targets: ["DropCore"]),
  ],
  targets: [
    .target(name: "DropCore"),
    .executableTarget(name: "FileDropUtility", dependencies: ["DropCore"]),
    .testTarget(name: "DropCoreTests", dependencies: ["DropCore"]),
  ]
)
