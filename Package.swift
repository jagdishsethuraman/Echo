// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Echo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Echo",
            targets: ["Echo"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Echo",
            path: "Sources/Echo"
        ),
        .testTarget(
            name: "EchoTests",
            dependencies: ["Echo"],
            path: "Tests"
        ),
    ]
)
