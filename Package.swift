// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyRecord",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyRecordAnalysis", targets: ["KeyRecordAnalysis"]),
        .library(name: "KeyRecordCore", targets: ["KeyRecordCore"]),
        .library(name: "KeyRecordCapture", targets: ["KeyRecordCapture"]),
        .library(name: "KeyRecordStore", targets: ["KeyRecordStore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "KeyRecordAnalysis", dependencies: ["KeyRecordCore"]),
        .testTarget(name: "KeyRecordAnalysisTests", dependencies: ["KeyRecordAnalysis"]),
        .target(name: "KeyRecordCore"),
        .target(name: "KeyRecordCapture", dependencies: ["KeyRecordCore"]),
        .target(name: "KeyRecordStore", dependencies: ["KeyRecordCore"]),
        .target(name: "KeyRecordTestSupport", dependencies: ["KeyRecordCore"], path: "Tests/KeyRecordTestSupport"),
        // Crash probe is a first-class build product so the store tests never have to
        // reconstruct a link line by walking ancestor directories for object files.
        // Bounded live-capture harness (L4). Test-only executable: not a product, never a
        // dependency of any library target.
        .executableTarget(name: "KeyRecordCaptureHarness",
                          dependencies: ["KeyRecordCore", "KeyRecordCapture"],
                          path: "Tests/KeyRecordCaptureHarness"),
        .executableTarget(name: "KeyRecordStoreCrashProbe",
                          dependencies: ["KeyRecordCore", "KeyRecordStore"],
                          path: "Tests/KeyRecordStoreCrashProbe"),
        .target(name: "KeyRecordMeasurement", path: "Tests/KeyRecordMeasurement"),
        .executableTarget(name: "KeyRecordResourceSampler",
                          dependencies: ["KeyRecordMeasurement"],
                          path: "Tests/KeyRecordResourceSampler",
                          linkerSettings: [.linkedFramework("SystemConfiguration")]),
        .testTarget(name: "KeyRecordMeasurementTests", dependencies: ["KeyRecordMeasurement", "KeyRecordCore"]),
        .testTarget(name: "KeyRecordCoreTests", dependencies: ["KeyRecordCore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordCaptureTests", dependencies: ["KeyRecordCapture", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordStoreTests", dependencies: ["KeyRecordStore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordIntegrationTests", dependencies: [
            "KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordTestSupport",
        ]),
    ],
    swiftLanguageModes: [.v6]
)
