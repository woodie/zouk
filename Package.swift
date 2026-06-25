// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zouk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "zouk", targets: ["zouk"])
    ],
    targets: [
        // Networking, model, and views live here so the test target can
        // @testable import them without the executable-testability caveats
        // that come with testing a target of type .executableTarget
        // directly (same split used in xctidy/XctidyKit).
        .target(name: "ZoukKit"),

        .executableTarget(
            name: "zouk",
            dependencies: ["ZoukKit"]
        ),

        .testTarget(
            name: "ZoukKitTests",
            dependencies: ["ZoukKit"]
        ),
    ]
)
