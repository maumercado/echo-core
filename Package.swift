// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioNexus",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(
            name: "AudioNexusCore",
            targets: ["AudioNexusCore"]
        ),
        .library(
            name: "AudioNexusCapture",
            targets: ["AudioNexusCapture"]
        ),
    ],
    targets: [
        .target(name: "AudioNexusCore"),
        .target(
            name: "AudioNexusCapture",
            dependencies: ["AudioNexusCore"]
        ),
        .testTarget(
            name: "AudioNexusCoreTests",
            dependencies: ["AudioNexusCore"]
        ),
        .testTarget(
            name: "AudioNexusCaptureTests",
            dependencies: ["AudioNexusCapture"]
        ),
    ]
)
