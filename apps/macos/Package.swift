// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Luxel",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "LuxelCore", targets: ["LuxelCore"]),
        .library(name: "LuxelCodecWebM", targets: ["LuxelCodecWebM"]),
        .executable(name: "Luxel", targets: ["LuxelApp"]),
        .executable(name: "luxel-cli", targets: ["LuxelCLIExecutable"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .executableTarget(
            name: "LuxelApp",
            dependencies: [
                "LuxelCore",
                "LuxelCodecWebM",
                "LuxelPresentation"
            ]
        ),
        .executableTarget(name: "LuxelCLIExecutable", dependencies: ["LuxelCLI"]),
        .target(
            name: "LuxelCLI",
            dependencies: [
                "LuxelCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(name: "LuxelPresentation", dependencies: ["LuxelCore"]),
        .target(
            name: "LuxelCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "LuxelCodecWebM",
            dependencies: [
                "LuxelCore",
                "CWebMCodecShims"
            ]
        ),
        .target(
            name: "CWebMCodecShims",
            dependencies: [
                "CVPX",
                "COpus"
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .binaryTarget(name: "CVPX", path: "Vendor/Artifacts/CVPX.xcframework"),
        .binaryTarget(name: "COpus", path: "Vendor/Artifacts/COpus.xcframework"),
        .testTarget(name: "LuxelCoreTests", dependencies: ["LuxelCore"]),
        .testTarget(name: "LuxelCodecWebMTests", dependencies: ["LuxelCodecWebM"]),
        .testTarget(
            name: "LuxelCLITests",
            dependencies: [
                "LuxelCLI",
                "LuxelCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "LuxelAppTests", dependencies: ["LuxelPresentation", "LuxelCore"])
    ]
)
