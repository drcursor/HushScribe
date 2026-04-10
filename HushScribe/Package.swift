// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HushScribe",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "ea500621819cadc46d6212af44624f2b45ab3240"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "a7be75801b4259d0c7d511c20b2310cdf79108b8"),
    ],
    targets: [
        .executableTarget(
            name: "HushScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/HushScribe",
            exclude: ["Info.plist", "HushScribe.entitlements", "Assets"]
        ),
    ]
)
