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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Echo",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Echo",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                         "-Xlinker", "-rpath", "-Xlinker", "@loader_path"])]
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
