// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whisperkit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WhisperKit",
            targets: ["WhisperKit"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-transformers"),
    ],
    targets: [
        .target(
            name: "WhisperKit",
            dependencies: [
                .product(name: "Transformers", package: "swift-transformers"),
            ]
        ),
    ]
)
