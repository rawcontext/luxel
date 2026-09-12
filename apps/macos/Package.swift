// swift-tools-version: 6.2

import PackageDescription

// Dependency resolution only. Bazel owns all application, library, and test targets.
let package = Package(
    name: "Luxel",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")
    ]
)
