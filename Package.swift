// swift-tools-version:6.0
// SPDX-License-Identifier: Apache-2.0
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
        .testTarget(
            name: "OopsieTests",
            dependencies: ["Oopsie"],
            path: "Tests/OopsieTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
