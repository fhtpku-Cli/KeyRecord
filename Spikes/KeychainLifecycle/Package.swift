// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeychainLifecycle",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lifecycle-preflight", targets: ["PreflightCLI"]),
        .library(name: "LifecycleHosted", targets: ["LifecycleHosted"]),
    ],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "LifecyclePreflight"),
        .target(name: "LifecycleHosted", dependencies: ["LifecyclePreflight",
            .product(name: "KeyRecordCore", package: "KeyRecord")],
            path: "Hosted", exclude: ["SignedCandidateBackend.swift", "KeychainLifecycleScenarioTests.swift",
                "AuthorizedProductKeychainClient.swift", "HostedProductKeychainBackendTests.swift", "HostedProductCompositionTests.swift"],
            sources: ["HostedLifecycleScenarioController.swift", "CounterWindowProductObserver.swift"]),
        .executableTarget(name: "PreflightCLI", dependencies: ["LifecyclePreflight"]),
        .testTarget(name: "KeychainLifecycleTests", dependencies: ["LifecyclePreflight"]),
        .testTarget(name: "LifecycleScenarioTests", dependencies: ["LifecyclePreflight", "LifecycleHosted"],
                    path: "Hosted", exclude: ["SignedCandidateBackend.swift", "HostedLifecycleScenarioController.swift", "CounterWindowProductObserver.swift",
                        "AuthorizedProductKeychainClient.swift", "HostedProductKeychainBackendTests.swift", "HostedProductCompositionTests.swift"],
                    sources: ["KeychainLifecycleScenarioTests.swift"]),
        .testTarget(name: "ProductObserverTests", dependencies: ["LifecyclePreflight", "LifecycleHosted",
            .product(name: "KeyRecordCore", package: "KeyRecord")]),
    ]
)
