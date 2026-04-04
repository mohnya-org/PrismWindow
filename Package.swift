// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PrismWindow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PrismWindow", targets: ["prism"]),
    ],
    targets: [
        .executableTarget(
            name: "prism"
        ),
    ]
)
