// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPowertools",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ZonesCore"),
        .target(name: "SwitcherCore"),
        .executableTarget(name: "MacPowertools", dependencies: ["ZonesCore", "SwitcherCore"]),
        .testTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"]),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
