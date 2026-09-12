// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeychainLifecycle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "lifecycle-preflight", targets: ["PreflightCLI"])],
    targets: [
        .target(name: "LifecyclePreflight"),
        .executableTarget(name: "PreflightCLI", dependencies: ["LifecyclePreflight"]),
        .testTarget(name: "KeychainLifecycleTests", dependencies: ["LifecyclePreflight"]),
    ]
)
