// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexPulse", targets: ["CodexPulse"])
    ],
    targets: [
        .executableTarget(
            name: "CodexPulse",
            path: "Sources/CodexPulse",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexPulseTests",
            dependencies: ["CodexPulse"],
            path: "Tests/CodexPulseTests"
        )
    ]
)
