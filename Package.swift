// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YouTalkingToMe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "YouTalkingToMe",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "YouTalkingToMe",
            exclude: ["Resources"],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Combine"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "YouTalkingToMeTests",
            dependencies: ["YouTalkingToMe"],
            path: "YouTalkingToMeTests"
        ),
    ]
)
