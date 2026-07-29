// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TiboResetCoin",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TiboResetCoin", targets: ["TiboResetCoin"])
    ],
    targets: [
        .executableTarget(
            name: "TiboResetCoin",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TiboResetCoinTests",
            dependencies: ["TiboResetCoin"]
        )
    ]
)
