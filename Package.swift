// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YouTalkingToMe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YouTalkingToMe",
            path: "YouTalkingToMe",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Combine"),
            ]
        ),
        .testTarget(
            name: "YouTalkingToMeTests",
            dependencies: ["YouTalkingToMe"],
            path: "YouTalkingToMeTests"
        ),
    ]
)
