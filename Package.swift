// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Burn",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/maferland/claude-usage-kit", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Burn",
            dependencies: [.product(name: "ClaudeUsageKit", package: "claude-usage-kit")],
            path: "Burn",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BurnTests",
            dependencies: ["Burn"],
            path: "BurnTests"
        )
    ]
)
