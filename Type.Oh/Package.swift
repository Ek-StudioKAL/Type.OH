// swift-tools-version:5.9
//
// SwiftPM manifest for building Type.OH on macOS 13 (Ventura) / Intel with a
// swift.org toolchain and the Command Line Tools SDK — no Xcode required.
// The Xcode project (Type.Oh.xcodeproj) is untouched; use build-app.sh to
// produce Type.Oh.app from this manifest.
import PackageDescription

// This manifest builds against the Command Line Tools' macOS 13.3 SDK, which
// lacks APIs that `#available` can't hide (e.g. SwiftUI's `openSettings`,
// `focusEffectDisabled`). Code that needs a newer SDK sits under
// `#if !TYPEOH_MACOS13_SDK`; the Xcode build never defines it.
let macOS13SDK: [SwiftSetting] = [.define("TYPEOH_MACOS13_SDK")]

let package = Package(
    name: "Type.Oh",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Type_Oh", targets: ["Type_Oh"]),
        .executable(name: "TypeOhStrip", targets: ["TypeOhStrip"]),
    ],
    dependencies: [
        // Vendored WhisperKit 0.10.1 — the newest release that compiles against
        // the macOS 13 SDK (later releases and argmax-oss-swift use MLState, a
        // macOS 15 Core ML API). Its swift-transformers 0.1.8 dependency is
        // vendored too, with a one-line patch for a swift.org compiler crash.
        // See Vendor/README.md.
        .package(path: "Vendor/WhisperKit"),
    ],
    targets: [
        .executableTarget(
            name: "Type_Oh",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Type.Oh",
            exclude: [
                "Assets.xcassets",
                "type-oh.icon",
                "Type.Oh.entitlements",
                "Icons", // copied into the app bundle by build-app.sh
            ],
            swiftSettings: macOS13SDK
        ),
        // Touch Bar Control Strip button, bundled into Type.Oh.app by
        // build-app.sh (see ControlStrip.swift for why it's a separate process).
        .executableTarget(
            name: "TypeOhStrip",
            path: "ControlStripHelper"
        ),
        .testTarget(
            name: "Type_OhTests",
            dependencies: ["Type_Oh"],
            path: "Type.OhTests",
            swiftSettings: macOS13SDK
        ),
    ]
)
