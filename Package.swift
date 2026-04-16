// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "clawbar",
    platforms: [
        .macOS(.v13),
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
            resources: [
                .copy("Resources/ClawbarLogoMaster.png"),
                .copy("Resources/ClawbarMenuBarTemplate18.png"),
                .copy("Resources/ClawbarMenuBarTemplate36.png"),
            ],
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
