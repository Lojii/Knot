// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnotWebService",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KnotWebService", targets: ["KnotWebService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.96.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.16.0"),
        .package(path: "../KnotStorage"),
    ],
    targets: [
        .target(
            name: "KnotWebService",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "KnotStorage", package: "KnotStorage"),
            ]
        ),
    ]
)
