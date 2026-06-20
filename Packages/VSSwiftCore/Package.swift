// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftCore", targets: ["VSSwiftCore"])
    ],
    dependencies: [
        .package(path: "../VSTestKit")
    ],
    targets: [
        .target(
            name: "VSSwiftCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftCoreTests",
            dependencies: ["VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
