// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lightio-cli",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LightioCore", targets: ["LightioCore"]),
        .executable(name: "lightiocli", targets: ["LightioCLI"]),
    ],
    targets: [
        .target(
            name: "LightioCore",
            path: "Sources/LightioCore"
        ),
        .executableTarget(
            name: "LightioCLI",
            dependencies: ["LightioCore"],
            path: "Sources/lightio"
        ),
        .testTarget(
            name: "LightioCoreTests",
            dependencies: ["LightioCore"],
            path: "Tests/LightioCoreTests"
        ),
    ]
)
