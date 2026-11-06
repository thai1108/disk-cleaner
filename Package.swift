// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskCleaner", targets: ["DiskCleaner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "DiskCleanerCore"),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: [
                "DiskCleanerCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "DiskCleanerCoreTests",
            dependencies: ["DiskCleanerCore"]
        ),
    ]
)
