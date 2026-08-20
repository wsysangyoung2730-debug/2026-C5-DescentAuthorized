// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DescentAuthorizedCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DescentAuthorizedCore",
            targets: ["DescentAuthorizedCore"]
        )
    ],
    targets: [
        .target(
            name: "DescentAuthorizedCore",
            path: "DescentAuthorized/Core"
        ),
        .testTarget(
            name: "DescentAuthorizedCoreTests",
            dependencies: ["DescentAuthorizedCore"],
            path: "DescentAuthorizedCoreTests"
        )
    ]
)
