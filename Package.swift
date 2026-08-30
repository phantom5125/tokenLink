// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "TokenLink",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TokenLinkCore", targets: ["TokenLinkCore"]),
    .library(name: "TokenLinkProviders", targets: ["TokenLinkProviders"]),
    .library(name: "TokenLinkDevice", targets: ["TokenLinkDevice"]),
    .executable(name: "tokenlink", targets: ["TokenLinkApp"]),
  ],
  targets: [
    .target(name: "TokenLinkCore"),
    .target(
      name: "TokenLinkProviders",
      dependencies: ["TokenLinkCore"],
      resources: [.process("Resources")]),
    .target(name: "TokenLinkDevice", dependencies: ["TokenLinkCore"]),
    .executableTarget(
      name: "TokenLinkApp",
      dependencies: ["TokenLinkCore", "TokenLinkProviders", "TokenLinkDevice"],
      resources: [.process("Resources")]),
    .testTarget(name: "TokenLinkCoreTests", dependencies: ["TokenLinkCore"]),
    .testTarget(
      name: "TokenLinkProviderTests",
      dependencies: ["TokenLinkCore", "TokenLinkProviders"],
      resources: [.process("Fixtures")]),
    .testTarget(
      name: "TokenLinkDeviceTests",
      dependencies: ["TokenLinkCore", "TokenLinkDevice"]),
    .testTarget(
      name: "TokenLinkAppTests",
      dependencies: [
        "TokenLinkApp",
        "TokenLinkCore",
        "TokenLinkProviders",
        "TokenLinkDevice",
      ]),
  ],
  swiftLanguageModes: [.v6]
)
