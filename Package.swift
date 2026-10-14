// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AIUsageBar", targets: ["AIUsageBar"]),
        .executable(name: "usagebar", targets: ["UsageBarCLI"]),
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "AIUsageBar", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageBarCLI", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ],
    swiftLanguageModes: [.v5]
)
