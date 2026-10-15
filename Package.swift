// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrustMe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrustMe", targets: ["TrustMe"]),
        .executable(name: "TrustMeDemo", targets: ["TrustMeDemo"]),
    ],
    targets: [
        .target(name: "TrustMe", dependencies: ["TrustMeProbe"]),
        .target(name: "TrustMeProbe"),
        .executableTarget(name: "TrustMeDemo", dependencies: ["TrustMe"]),
        // Dev tool: composites real guide panels over a backdrop and screenshots them.
        .executableTarget(name: "TrustMeRender", dependencies: ["TrustMe"]),
        // Minimal executable linking TrustMe, so tests can exercise the TCC probe.
        .executableTarget(name: "TrustMeProbeHost", dependencies: ["TrustMe"], path: "Tests/ProbeHost"),
        // Another process with a real window, standing in for System Settings.
        .executableTarget(name: "TrustMeWindowHost", path: "Tests/WindowHost"),
        .testTarget(name: "TrustMeTests", dependencies: ["TrustMe", "TrustMeProbeHost", "TrustMeWindowHost"]),
    ]
)
