// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Parakeet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Parakeet", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "HotKey", package: "HotKey")
            ],
            path: "App"
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "HotKey", package: "HotKey")
            ],
            path: "Core"
        )
    ]
)
