// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flip",
    platforms: [.macOS(.v14)],
    targets: [
        // Declares one private accessibility symbol that Swift cannot reach on
        // its own. See the header for what it is and why it is needed.
        .target(name: "CAXShim"),
        .executableTarget(
            name: "Flip",
            dependencies: ["CAXShim"],
            // AXObserver callbacks are bare C function pointers with no captured
            // context, which Swift 6 strict concurrency has no way to reason
            // about. Harden once the window store exists and its shape is settled;
            // fighting Sendable before then buys nothing.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
    ]
)
