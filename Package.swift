// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TrackPinch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TrackPinchCore",
            targets: ["TrackPinchCore"]
        ),
        .executable(
            name: "TrackPinch",
            targets: ["TrackPinch"]
        ),
    ],
    targets: [
        .target(
            name: "TrackPinchCore"
        ),
        .executableTarget(
            name: "TrackPinch",
            dependencies: ["TrackPinchCore"]
        ),
        .testTarget(
            name: "TrackPinchCoreTests",
            dependencies: ["TrackPinchCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
