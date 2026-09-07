// swift-tools-version: 6.0
import PackageDescription

// Game #2 lives in a package, not a folder, so the compiler enforces the
// extraction boundary (P39): a package cannot import an app target, so every
// forbidden dependency on OurApp is a build error rather than a review note.
let package = Package(
    name: "FarshoreKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FarshoreKit", targets: ["FarshoreKit"])
    ],
    targets: [
        .target(
            name: "FarshoreKit",
            resources: [.process("Resources")],
            // Matches the app exactly (SWIFT_VERSION = 5.0). Swift 6 mode
            // across the boundary would mean fighting strict concurrency in a
            // slice whose job is proving the boundary works.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "FarshoreKitTests", dependencies: ["FarshoreKit"])
    ]
)
