// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "prism",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Prism", targets: ["prism"]),
    ],
    targets: [
        .executableTarget(
            name: "prism"
        ),
    ]
)
