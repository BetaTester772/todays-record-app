// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TurnTable",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TurnTable",
            path: "Sources/TurnTable"
        ),
        .testTarget(
            name: "TurnTableTests",
            dependencies: ["TurnTable"],
            path: "Tests/TurnTableTests"
        ),
    ]
)
