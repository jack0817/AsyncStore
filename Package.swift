// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncStore",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "AsyncStore",
            targets: ["AsyncStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "AsyncStore",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ]
        ),
        .testTarget(
            name: "AsyncStoreTests",
            dependencies: ["AsyncStore"]),
    ]
)

