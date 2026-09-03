// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Argon2idSwiftNative",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "Argon2idSwiftNative",
            targets: ["Argon2idSwiftNative"]
        )
    ],
    targets: [
        .target(
            name: "Argon2idSwiftNative"
        ),
        .testTarget(
            name: "Argon2idSwiftNativeTests",
            dependencies: ["Argon2idSwiftNative"]
        )
    ]
)
