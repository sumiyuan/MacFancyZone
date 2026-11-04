// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPowertools",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ZonesCore"),
        .executableTarget(name: "MacPowertools", dependencies: ["ZonesCore"]),
        .testTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"]),
    ]
)
