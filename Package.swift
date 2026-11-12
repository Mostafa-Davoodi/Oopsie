// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Oopsie",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Oopsie",
            path: "Sources/Oopsie",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
