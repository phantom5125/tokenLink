// swift-tools-version: 6.2
import Foundation
import PackageDescription

// 本机只有 Command Line Tools（无 Xcode）时，Swift Testing 不在默认搜索路径，
// 需要显式指向 CLT 内的 Testing.framework 与宏插件；装有 Xcode 的机器（含 CI）不需要。
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let needsCLTTestingPaths = !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    && FileManager.default.fileExists(atPath: "\(cltFrameworks)/Testing.framework")

let testSwiftSettings: [SwiftSetting] = needsCLTTestingPaths
    ? [.unsafeFlags(["-F", cltFrameworks, "-plugin-path", cltTestingPlugin])]
    : []
let testLinkerSettings: [LinkerSetting] = needsCLTTestingPaths
    ? [.unsafeFlags([
        "-F", cltFrameworks, "-framework", "Testing",
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
    ])]
    : []

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
        .testTarget(
            name: "TokenLinkCoreTests",
            dependencies: ["TokenLinkCore"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings),
        .target(name: "TokenLinkProviders", dependencies: ["TokenLinkCore"]),
        .testTarget(
            name: "TokenLinkProviderTests",
            dependencies: ["TokenLinkCore", "TokenLinkProviders"],
            resources: [.process("Fixtures")],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings),
        .target(name: "TokenLinkDevice", dependencies: ["TokenLinkCore"]),
        .testTarget(
            name: "TokenLinkDeviceTests",
            dependencies: ["TokenLinkCore", "TokenLinkDevice"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings),
    ],
    swiftLanguageModes: [.v6]
)
