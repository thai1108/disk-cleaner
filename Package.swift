// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskCleaner", targets: ["DiskCleaner"]),
    ],
    targets: [
        .target(name: "DiskCleanerCore"),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: ["DiskCleanerCore"]
        ),
        .testTarget(
            name: "DiskCleanerCoreTests",
            dependencies: ["DiskCleanerCore"]
        ),
    ]
)
