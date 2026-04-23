// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HushScribe",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "ea500621819cadc46d6212af44624f2b45ab3240"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "7e2b7107be52ffbfe488f3c7987d3f52c1858b4b"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.9"),
    ],
    targets: [
        .executableTarget(
            name: "HushScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Hub", package: "swift-transformers"),
            ],
            path: "Sources/HushScribe",
            exclude: ["Info.plist", "HushScribe.entitlements", "Assets"]
        ),
    ]
)
