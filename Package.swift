// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PingMonitor",
            path: "Sources/PingMonitor"
        )
    ]
)
