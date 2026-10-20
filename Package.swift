// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TodaysRecord",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TodaysRecord",
            path: "Sources/TodaysRecord"
        )
    ]
)
