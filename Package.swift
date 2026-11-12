// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Oopsie",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Oopsie",
            dependencies: ["SwiftTerm"],
            path: "Sources/Oopsie"
        ),
    ]
)
