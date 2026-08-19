// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TokenLink",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenLinkCore", targets: ["TokenLinkCore"]),
        .library(name: "TokenLinkProviders", targets: ["TokenLinkProviders"]),
    ],
    targets: [
        .target(name: "TokenLinkCore"),
        .target(name: "TokenLinkProviders", dependencies: ["TokenLinkCore"]),
        .testTarget(name: "TokenLinkCoreTests", dependencies: ["TokenLinkCore"]),
        .testTarget(
            name: "TokenLinkProviderTests",
            dependencies: ["TokenLinkCore", "TokenLinkProviders"]),
    ],
    swiftLanguageModes: [.v6]
)
