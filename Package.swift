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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
        .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Ginmi",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "Fuse", package: "fuse-swift")
            ]
        ),
        .testTarget(
            name: "GinmiTests",
            dependencies: ["Ginmi"]
        )
    ]
)
