// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LimitBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LimitBar", targets: ["LimitBar"])
    ],
    targets: [
        .executableTarget(
            name: "LimitBar",
            path: "Sources/LimitBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "LimitBarTests",
            dependencies: ["LimitBar"]
        )
    ]
)
