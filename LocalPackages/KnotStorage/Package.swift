// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnotStorage",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "KnotStorage", targets: ["KnotStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "KnotStorage",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .testTarget(
            name: "KnotStorageTests",
            dependencies: ["KnotStorage"]
        ),
    ]
)
