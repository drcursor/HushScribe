// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HushScribe",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "ea500621819cadc46d6212af44624f2b45ab3240"),
    ],
    targets: [
        .executableTarget(
            name: "HushScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Tome",
            exclude: ["Info.plist", "HushScribe.entitlements", "Assets"]
        ),
    ]
)
