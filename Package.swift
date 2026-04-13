// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ModelsBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ModelsBar", targets: ["ModelsBar"])
    ],
    targets: [
        .executableTarget(
            name: "ModelsBar",
            path: "Sources/ModelsBar"
        )
    ]
)
