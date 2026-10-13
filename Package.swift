// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyRecord",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyRecordDeviceRead", targets: ["KeyRecordDeviceRead"]),
        .library(name: "KeyRecordMappings", targets: ["KeyRecordMappings"]),
        .library(name: "KeyRecordConfigurationRead", targets: ["KeyRecordConfigurationRead"]),
        .library(name: "KeyRecordAnalysis", targets: ["KeyRecordAnalysis"]),
        .library(name: "KeyRecordCore", targets: ["KeyRecordCore"]),
        .library(name: "KeyRecordCapture", targets: ["KeyRecordCapture"]),
        .library(name: "KeyRecordStore", targets: ["KeyRecordStore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "KeyRecordLimitedXZ", linkerSettings: [.linkedLibrary("lzma.5")]),
        .target(name: "KeyRecordDeviceRead", dependencies: ["KeyRecordMappings", "KeyRecordConfigurationRead", "KeyRecordLimitedXZ"]),
        .testTarget(name: "KeyRecordDeviceReadTests", dependencies: ["KeyRecordDeviceRead", "KeyRecordMappings"]),
        .target(name: "KeyRecordMappings", dependencies: ["KeyRecordCore", "KeyRecordAnalysis", "KeyRecordStore", "KeyRecordConfigurationRead"]),
        .testTarget(name: "KeyRecordMappingsTests", dependencies: ["KeyRecordMappings"]),
        .executableTarget(name: "KeyRecordMappingCrashProbe", dependencies: ["KeyRecordCore", "KeyRecordAnalysis", "KeyRecordStore", "KeyRecordMappings"], path: "Tests/KeyRecordMappingCrashProbe"),
        .executableTarget(name: "KeyRecordFirmwareIntegrationProbe", dependencies: ["KeyRecordCore", "KeyRecordStore", "KeyRecordMappings", "KeyRecordDeviceRead"], path: "Tests/KeyRecordFirmwareIntegrationProbe"),
        .target(name: "KeyRecordConfigurationRead"),
        .target(name: "KeyRecordAnalysis", dependencies: ["KeyRecordCore", "KeyRecordConfigurationRead"]),
        .testTarget(name: "KeyRecordAnalysisTests", dependencies: ["KeyRecordAnalysis", "KeyRecordConfigurationRead"]),
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
        .executableTarget(name: "KeyRecordPerformanceTrial",
                          dependencies: ["KeyRecordMeasurement"],
                          path: "Tests/KeyRecordPerformanceTrial",
                          exclude: ["TrialInfo.plist"],
                          linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "KeyRecordMeasurementTests", dependencies: ["KeyRecordMeasurement", "KeyRecordCore"]),
        .testTarget(name: "KeyRecordCoreTests", dependencies: ["KeyRecordCore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordCaptureTests", dependencies: ["KeyRecordCapture", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordStoreTests", dependencies: ["KeyRecordStore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordIntegrationTests", dependencies: [
            "KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordMeasurement",
            "KeyRecordTestSupport",
        ]),
    ],
    swiftLanguageModes: [.v6]
)
