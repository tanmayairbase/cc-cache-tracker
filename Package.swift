// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CacheTracker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CacheTracker",
            path: "Sources/CacheTracker"
        )
    ]
)
