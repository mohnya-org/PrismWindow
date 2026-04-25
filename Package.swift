// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PrismWindow",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "PrismWindow", targets: ["prism"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "prism",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
