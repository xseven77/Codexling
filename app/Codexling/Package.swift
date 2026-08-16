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
        .target(
            name: "CZSTD",
            path: "Sources/CZSTD",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("zstd"),
                .unsafeFlags(["-L", "/opt/homebrew/lib", "-Xlinker", "-w"])
            ]
        ),
        .executableTarget(
            name: "Codexling",
            dependencies: ["CZSTD"],
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
            dependencies: ["Codexling", "CZSTD"],
            path: "Tests/CodexlingTests"
        )
    ]
)
