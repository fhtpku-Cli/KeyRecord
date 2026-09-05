// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Phase0Spikes",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Phase0Support", targets: ["Phase0Support"]),
        .executable(name: "Phase0Probe", targets: ["Phase0Probe"]),
        .executable(name: "EvidenceValidator", targets: ["EvidenceValidator"]),
    ],
    targets: [
        .target(name: "Phase0Support"),
        .executableTarget(name: "Phase0Probe", dependencies: ["Phase0Support"]),
        .executableTarget(name: "EvidenceValidator", dependencies: ["Phase0Support"]),
        .testTarget(
            name: "Phase0SupportTests",
            dependencies: ["Phase0Support"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "Phase0ProbeTests", dependencies: ["Phase0Probe"]),
        .testTarget(name: "EvidenceValidatorTests", dependencies: ["EvidenceValidator", "Phase0Probe"]),
    ]
)
