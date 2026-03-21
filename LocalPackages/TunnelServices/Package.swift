// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunnelServices",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TunnelServices", targets: ["TunnelServices"]),
    ],
    dependencies: [
        // SwiftNIO
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.96.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.1"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.33.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.41.0"),
        // Crypto & Certificates
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.3.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.18.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.6.0"),
        // Database
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.16.0"),
        // Networking
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket.git", from: "7.6.5"),
        // Local QUIC packages
        .package(path: "../SwiftQuiche"),
        .package(path: "../SwiftLsquic"),
    ],
    targets: [
        .systemLibrary(
            name: "Czlib",
            pkgConfig: nil,
            providers: [
                .brew(["zlib"]),
                .apt(["zlib1g-dev"]),
            ]
        ),
        .target(
            name: "TunnelServices",
            dependencies: [
                // SwiftNIO products
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOHPACK", package: "swift-nio-http2"),
                // Crypto
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                // Database
                .product(name: "SQLite", package: "SQLite.swift"),
                // Networking
                .product(name: "CocoaAsyncSocket", package: "CocoaAsyncSocket"),
                // QUIC (all platforms)
                .product(name: "SwiftQuiche", package: "SwiftQuiche"),
                .product(name: "SwiftLsquic", package: "SwiftLsquic"),
                // System
                "Czlib",
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "TunnelServicesTests",
            dependencies: ["TunnelServices"],
            path: "Tests/TunnelServicesTests"
        ),
    ]
)
