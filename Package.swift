// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "AsyncStore",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AsyncStore",
            targets: ["AsyncStore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "509.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AsyncStore",
            dependencies: [
                "AsyncStoreMacros",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .macro(
            name: "AsyncStoreMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "AsyncStoreTests",
            dependencies: ["AsyncStore"]
        ),
        .testTarget(
            name: "AsyncStoreMacroTests",
            dependencies: ["AsyncStore"]
        ),
    ]
)

