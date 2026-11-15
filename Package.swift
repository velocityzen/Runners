// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Runners",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "RunnersKit", targets: ["RunnersKit"]),
        .executable(name: "runners", targets: ["runners"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.5.0"),
        .package(url: "https://github.com/velocityzen/fp-swift", from: "4.4.2"),
        .package(url: "https://github.com/velocityzen/fp-swift-pipe", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "RunnersKit",
            dependencies: [
                .product(name: "FP", package: "fp-swift"),
                .product(name: "FPRetry", package: "fp-swift"),
                .product(name: "FPPipe", package: "fp-swift-pipe"),
            ],
            swiftSettings: callerIsolation
        ),
        .executableTarget(
            name: "runners",
            dependencies: [
                "RunnersKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "FP", package: "fp-swift"),
            ],
            swiftSettings: callerIsolation
        ),
        .testTarget(
            name: "RunnersKitTests",
            dependencies: [
                "RunnersKit",
                .product(name: "FPRetry", package: "fp-swift"),
            ],
            swiftSettings: callerIsolation
        ),
    ]
)

// Async functions and closures run on the caller's actor.
var callerIsolation: [SwiftSetting] { [.enableUpcomingFeature("NonisolatedNonsendingByDefault")] }
