// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Codexling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Codexling", targets: ["Codexling"])
    ],
    targets: [
        .executableTarget(
            name: "Codexling",
            path: "Sources/Codexling",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexlingTests",
            dependencies: ["Codexling"],
            path: "Tests/CodexlingTests"
        )
    ]
)
