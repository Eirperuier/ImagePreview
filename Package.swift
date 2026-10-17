// swift-tools-version: 6.0

import PackageDescription

/// Loupe: a photo viewer that opens from the thumbnail you tapped and closes back into it.
/// iPhone, iPad, Mac (Catalyst and AppKit) and Vision Pro, with a SwiftUI and a UIKit/AppKit API.
let package = Package(
    name: "Loupe",
    platforms: [.iOS(.v17), .macCatalyst(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "Loupe", targets: ["Loupe"]),
    ],
    targets: [
        .target(name: "Loupe", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "LoupeTests", dependencies: ["Loupe"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
