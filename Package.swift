// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TokenLink",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TokenLinkCore", targets: ["TokenLinkCore"])],
    targets: [
        .target(name: "TokenLinkCore"),
        .testTarget(name: "TokenLinkCoreTests", dependencies: ["TokenLinkCore"]),
    ],
    swiftLanguageModes: [.v6]
)
