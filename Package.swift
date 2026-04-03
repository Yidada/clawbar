// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "clawbar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ClawbarKit", targets: ["ClawbarKit"]),
        .executable(name: "Clawbar", targets: ["Clawbar"]),
    ],
    targets: [
        .target(
            name: "ClawbarKit",
            path: "Sources/ClawbarKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Clawbar",
            dependencies: ["ClawbarKit"],
            path: "Sources/Clawbar",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ClawbarTests",
            dependencies: ["Clawbar", "ClawbarKit"],
            path: "Tests/ClawbarTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
