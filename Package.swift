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
        .executableTarget(
            name: "Flip",
            dependencies: ["CAXShim"],
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
            dependencies: ["Flip"],
            path: "tests/FlipTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
