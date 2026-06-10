// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TokenMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenMeter", targets: ["TokenMeter"])
    ],
    targets: [
        .executableTarget(
            name: "TokenMeter"
        )
    ]
)
