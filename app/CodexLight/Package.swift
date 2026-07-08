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
            path: "Sources/CodexLight"
        )
    ]
)
