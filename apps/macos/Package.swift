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
        .library(name: "LuxelCodecAV1", targets: ["LuxelCodecAV1"]),
        .executable(name: "Luxel", targets: ["LuxelApp"]),
        .executable(name: "luxel-cli", targets: ["LuxelCLIExecutable"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5")
    ],
    targets: [
        .executableTarget(
            name: "LuxelApp",
            dependencies: [
                "LuxelCore",
                "LuxelCodecAV1",
                "LuxelCodecWebM",
                "LuxelPresentation"
            ]
        ),
        .executableTarget(name: "LuxelCLIExecutable", dependencies: ["LuxelCLI"]),
        .target(
            name: "LuxelCLI",
            dependencies: [
                "LuxelCodecAV1",
                "LuxelCodecWebM",
                "LuxelCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(name: "LuxelPresentation", dependencies: ["LuxelCore"]),
        .target(
            name: "LuxelCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "LuxelCodecAV1",
            dependencies: [
                "LuxelCore",
                "CAV1CodecShims"
            ]
        ),
        .target(
            name: "CAV1CodecShims",
            dependencies: [
                "CSVTAV1"
            ],
            linkerSettings: [
                .linkedLibrary("c++")
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
        .binaryTarget(name: "CSVTAV1", path: "Vendor/Artifacts/CSVTAV1.xcframework"),
        .testTarget(name: "LuxelCoreTests", dependencies: ["LuxelCore"]),
        .testTarget(name: "LuxelCodecAV1Tests", dependencies: ["LuxelCodecAV1"]),
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
