// swift-tools-version: 6.0
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
            path: "Tests/EchoTests"
        ),
    ],
    // The app is still written against the Swift 5 concurrency model; adopt
    // Swift 6 language mode incrementally (see CORE-01 in CODE_REVIEW.md).
    swiftLanguageModes: [.v5]
)
