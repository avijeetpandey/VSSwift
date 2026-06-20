// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftEngine", targets: ["VSSwiftEngine"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSTestKit")
    ],
    targets: [
        .target(
            name: "VSSwiftEngine",
            dependencies: ["VSSwiftCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftEngineTests",
            dependencies: ["VSSwiftEngine", "VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
