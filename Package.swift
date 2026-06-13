// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Luxel",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "LuxelCore", targets: ["LuxelCore"]),
        .executable(name: "Luxel", targets: ["LuxelApp"])
    ],
    targets: [
        .executableTarget(name: "LuxelApp", dependencies: ["LuxelCore", "LuxelPresentation"]),
        .target(name: "LuxelPresentation", dependencies: ["LuxelCore"]),
        .target(name: "LuxelCore"),
        .testTarget(name: "LuxelCoreTests", dependencies: ["LuxelCore"]),
        .testTarget(name: "LuxelAppTests", dependencies: ["LuxelPresentation", "LuxelCore"])
    ]
)
