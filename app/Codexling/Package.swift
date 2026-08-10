// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Codexling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Codexling", targets: ["Codexling"]),
        .executable(name: "CodexlingAgentBridge", targets: ["CodexlingAgentBridge"])
    ],
    targets: [
        .executableTarget(
            name: "Codexling",
            path: "Sources/Codexling",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CodexlingAgentBridge",
            path: "Sources/CodexlingAgentBridge"
        ),
        .testTarget(
            name: "CodexlingTests",
            dependencies: ["Codexling"],
            path: "Tests/CodexlingTests"
        )
    ]
)
