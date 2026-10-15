// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "DemoVideos",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        // Wallpaper capture, the fake desktop, and a system-style alert shared by both demos.
        .target(name: "DemoSupport", swiftSettings: v5),
        // Full-screen storm of system permission popups.
        .executableTarget(name: "PopupStorm", dependencies: ["DemoSupport"], swiftSettings: v5),
        // TrustMe's window and a simulated System Settings, with the drag animated.
        .executableTarget(
            name: "DragDemo",
            dependencies: ["DemoSupport", .product(name: "TrustMe", package: "TrustMe")],
            swiftSettings: v5
        ),
    ]
)
