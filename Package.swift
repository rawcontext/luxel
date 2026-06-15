// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Luxel",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "LuxelCore", targets: ["LuxelCore"]),
        .executable(name: "Luxel", targets: ["LuxelApp"]),
        .executable(name: "luxel-cli", targets: ["LuxelCLIExecutable"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMajor(from: "12.14.0")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .executableTarget(
            name: "LuxelApp",
            dependencies: [
                "LuxelCore",
                "LuxelPresentation",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk")
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
        .target(name: "LuxelCore"),
        .testTarget(name: "LuxelCoreTests", dependencies: ["LuxelCore"]),
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
