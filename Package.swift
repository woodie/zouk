// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zouk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "zouk", targets: ["zouk"])
    ],
    dependencies: [
        // Test-only -- lets ZoukKitTests be converted to real Quick
        // describe/context/it specs (see docs/COWORK.md task #16), matching
        // xctidy/next-caltrain-swift's spec style. Wired up ahead of the
        // conversion itself so the imports are just there when needed.
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
        // Local path ahead of humane-swift's v0.1.0 tag being pushed -- switch to a
        // version pin once it's tagged on GitHub.
        .package(path: "../humane-swift"),
    ],
    targets: [
        // Networking, model, and views live here so the test target can
        // @testable import them without the executable-testability caveats
        // that come with testing a target of type .executableTarget
        // directly (same split used in xctidy/XctidyKit).
        .target(
            name: "ZoukKit",
            dependencies: [.product(name: "Humane", package: "humane-swift")],
            resources: [.process("Resources")]
        ),

        .executableTarget(
            name: "zouk",
            dependencies: ["ZoukKit"]
        ),

        .testTarget(
            name: "ZoukKitTests",
            dependencies: [
                "ZoukKit",
                .product(name: "Quick", package: "Quick"),
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
    ]
)
