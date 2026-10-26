// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BTHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BTHubCore"),
        .executableTarget(name: "BTHub", dependencies: ["BTHubCore"]),
        .testTarget(name: "BTHubCoreTests", dependencies: ["BTHubCore"]),
    ]
)
