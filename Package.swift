// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flip",
    platforms: [.macOS(.v14)],
    // Every target spells out its path: the top level directories are lower case,
    // so SwiftPM's Sources/<target> no longer matches. Leaving it implicit would
    // work by accident on a case-insensitive volume and fail the first time the
    // repository is checked out on a case-sensitive one.
    targets: [
        // Declares one private accessibility symbol that Swift cannot reach on
        // its own. See the header for what it is and why it is needed.
        .target(name: "CAXShim", path: "src/CAXShim"),
        // The wire format between the application and the `flip` command. Shared
        // rather than written twice: the two ship together but build separately,
        // so this is the one thing that must not be able to drift.
        .target(name: "FlipControl", path: "src/FlipControl"),
        .executableTarget(
            name: "FlipCLI",
            dependencies: ["FlipControl"],
            path: "src/FlipCLI"
        ),
        .executableTarget(
            name: "Flip",
            dependencies: ["CAXShim", "FlipControl"],
            path: "src/Flip",
            // AXObserver callbacks are bare C function pointers with no captured
            // context, which Swift 6 strict concurrency has no way to reason
            // about. Harden once the window store exists and its shape is settled;
            // fighting Sendable before then buys nothing.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        .testTarget(
            name: "FlipTests",
            dependencies: ["Flip", "FlipControl"],
            path: "tests/FlipTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
