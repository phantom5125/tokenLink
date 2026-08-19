// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TokenLink",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenLinkCore", targets: ["TokenLinkCore"]),
        .library(name: "TokenLinkProviders", targets: ["TokenLinkProviders"]),
        .library(name: "TokenLinkDevice", targets: ["TokenLinkDevice"]),
    ],
    targets: [
        .target(name: "TokenLinkCore"),
        .target(name: "TokenLinkProviders", dependencies: ["TokenLinkCore"]),
        .target(name: "TokenLinkDevice", dependencies: ["TokenLinkCore"]),
        .testTarget(name: "TokenLinkCoreTests", dependencies: ["TokenLinkCore"]),
        .testTarget(
            name: "TokenLinkProviderTests",
            dependencies: ["TokenLinkCore", "TokenLinkProviders"],
            resources: [.process("Fixtures")]),
        .testTarget(
            name: "TokenLinkDeviceTests",
            dependencies: ["TokenLinkCore", "TokenLinkDevice"]),
    ],
    swiftLanguageModes: [.v6]
)
