// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexLight", targets: ["CodexLight"])
    ],
    targets: [
        .executableTarget(
            name: "CodexLight",
            path: "Sources/CodexLight",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexLightTests",
            dependencies: ["CodexLight"],
            path: "Tests/CodexLightTests"
        )
    ]
)
