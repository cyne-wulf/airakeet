// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "airakeet-spike",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "airakeet-spike",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
    ]
)
