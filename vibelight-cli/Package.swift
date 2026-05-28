// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vibelight-cli",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibelightCore", targets: ["VibelightCore"]),
        .executable(name: "vibelight", targets: ["vibelight"]),
    ],
    targets: [
        .target(
            name: "VibelightCore",
            path: "Sources/VibelightCore"
        ),
        .executableTarget(
            name: "vibelight",
            dependencies: ["VibelightCore"],
            path: "Sources/vibelight"
        ),
        .testTarget(
            name: "VibelightCoreTests",
            dependencies: ["VibelightCore"],
            path: "Tests/VibelightCoreTests"
        ),
    ]
)
