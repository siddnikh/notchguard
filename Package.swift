// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Notchguard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "notchguard", targets: ["Notchguard"]),
        .library(name: "NotchguardCore", targets: ["NotchguardCore"])
    ],
    targets: [
        .target(name: "NotchguardCore"),
        .executableTarget(name: "Notchguard", dependencies: ["NotchguardCore"]),
        .testTarget(name: "NotchguardCoreTests", dependencies: ["NotchguardCore"])
    ]
)

