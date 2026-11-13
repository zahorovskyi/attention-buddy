// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "attention-buddy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "attention-buddy", targets: ["attention-buddy"])
    ],
    targets: [
        // Pure logic: state files, priorities, the "seen" timer, animation scheduling.
        // No AppKit, so everything here is unit-testable.
        .target(name: "AttentionCore"),
        // AppKit and Core Animation: the floating window, icon layers, menu and app wiring.
        .target(name: "AttentionUI", dependencies: ["AttentionCore"]),
        // Thin command-line entry point.
        .executableTarget(name: "attention-buddy", dependencies: ["AttentionCore", "AttentionUI"]),
        .testTarget(name: "AttentionCoreTests", dependencies: ["AttentionCore"]),
        .testTarget(name: "AttentionUITests", dependencies: ["AttentionUI", "AttentionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
