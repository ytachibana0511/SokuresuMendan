// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SokuresuMendanApp",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SokuresuMendanApp",
            targets: ["SokuresuMendanApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SokuresuMendanApp"
        ),
        .testTarget(
            name: "SokuresuMendanAppTests",
            dependencies: ["SokuresuMendanApp"]
        )
    ]
)
