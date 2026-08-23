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
        .executable(
            name: "luxel-transcription-benchmark",
            targets: ["LuxelTranscriptionBenchmark"]
        ),
        .executable(
            name: "luxel-media-benchmark",
            targets: ["LuxelMediaBenchmark"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.6"
        )
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
        .executableTarget(
            name: "LuxelTranscriptionBenchmark",
            dependencies: [
                "LuxelCore",
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "LuxelMediaBenchmark",
            dependencies: [
                "LuxelCore",
                "LuxelCodecAV1",
                "LuxelCodecWebM"
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
        .target(
            name: "LuxelTestSupport",
            dependencies: ["LuxelCore"],
            path: "Tests/LuxelTestSupport"
        ),
        .testTarget(
            name: "LuxelCoreTests",
            dependencies: ["LuxelCore", "LuxelTestSupport"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "LuxelCodecAV1Tests",
            dependencies: ["LuxelCodecAV1", "LuxelTestSupport"]
        ),
        .testTarget(
            name: "LuxelCodecWebMTests",
            dependencies: ["LuxelCodecWebM", "LuxelTestSupport"]
        ),
        .testTarget(
            name: "LuxelAppTests",
            dependencies: ["LuxelApp", "LuxelPresentation", "LuxelCore", "LuxelTestSupport"]
        )
    ]
)
