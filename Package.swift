// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Burn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Burn",
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
