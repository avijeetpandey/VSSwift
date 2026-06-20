// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftLSP",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftLSP", targets: ["VSSwiftLSP"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSTestKit")
    ],
    targets: [
        .target(
            name: "VSSwiftLSP",
            dependencies: ["VSSwiftCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftLSPTests",
            dependencies: ["VSSwiftLSP", "VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
