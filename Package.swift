// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ginmi",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Ginmi", targets: ["Ginmi"])
    ],
    dependencies: [
        .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Ginmi",
            dependencies: [
                .product(name: "Fuse", package: "fuse-swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GinmiTests",
            dependencies: ["Ginmi"]
        )
    ]
)
