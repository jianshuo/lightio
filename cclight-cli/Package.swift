// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cclight-cli",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CCLightCore", targets: ["CCLightCore"]),
        .executable(name: "cclightcli", targets: ["CCLightCLI"]),
    ],
    targets: [
        .target(
            name: "CCLightCore",
            path: "Sources/CCLightCore"
        ),
        .executableTarget(
            name: "CCLightCLI",
            dependencies: ["CCLightCore"],
            path: "Sources/cclight"
        ),
        .testTarget(
            name: "CCLightCoreTests",
            dependencies: ["CCLightCore"],
            path: "Tests/CCLightCoreTests"
        ),
    ]
)
