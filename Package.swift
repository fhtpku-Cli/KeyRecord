// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyRecord",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyRecordCore", targets: ["KeyRecordCore"]),
        .library(name: "KeyRecordCapture", targets: ["KeyRecordCapture"]),
        .library(name: "KeyRecordStore", targets: ["KeyRecordStore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "KeyRecordCore"),
        .target(name: "KeyRecordCapture", dependencies: ["KeyRecordCore"]),
        .target(name: "KeyRecordStore", dependencies: ["KeyRecordCore"]),
        .target(name: "KeyRecordTestSupport", dependencies: ["KeyRecordCore"], path: "Tests/KeyRecordTestSupport"),
        .testTarget(name: "KeyRecordCoreTests", dependencies: ["KeyRecordCore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordCaptureTests", dependencies: ["KeyRecordCapture", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordStoreTests", dependencies: ["KeyRecordStore", "KeyRecordTestSupport"]),
        .testTarget(name: "KeyRecordIntegrationTests", dependencies: [
            "KeyRecordCore", "KeyRecordCapture", "KeyRecordStore", "KeyRecordTestSupport",
        ]),
    ],
    swiftLanguageModes: [.v6]
)
