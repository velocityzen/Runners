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
        .package(url: "https://github.com/apple/swift-system", from: "1.6.0"),
        .package(url: "https://github.com/velocityzen/fp-swift", from: "4.8.0"),
        .package(url: "https://github.com/velocityzen/fp-swift-service", from: "0.2.1"),
        .package(url: "https://github.com/velocityzen/ProgramStatus", from: "0.4.1"),
        .package(url: "https://github.com/velocityzen/fp-swift-pipe", from: "2.5.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-crypto", from: "5.1.1"),
    ],
    targets: [
        .target(
            name: "RunnersKit",
            dependencies: [
                .product(name: "FP", package: "fp-swift"),
                .product(name: "FPRetry", package: "fp-swift"),
                .product(name: "FPPipe", package: "fp-swift-pipe"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                // SHA-256 and HMAC for signing AWS requests: CryptoKit on Apple platforms.
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            swiftSettings: callerIsolation
        ),
        .executableTarget(
            name: "runners",
            dependencies: [
                "RunnersKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "FP", package: "fp-swift"),
                .product(name: "ProcessSignals", package: "fp-swift-service"),
                .product(name: "ProgramStatus", package: "ProgramStatus"),
            ],
            swiftSettings: callerIsolation
        ),
        .testTarget(
            name: "runnersTests",
            dependencies: [
                "runners",
                "RunnersKit",
                .product(name: "Configuration", package: "swift-configuration"),
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
