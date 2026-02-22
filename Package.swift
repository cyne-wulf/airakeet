// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Airakeet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Airakeet", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "App"
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Core"
        )
    ]
)
