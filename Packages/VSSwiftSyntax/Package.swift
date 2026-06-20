// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftSyntax",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftSyntax", targets: ["VSSwiftSyntax"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSTestKit"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .target(
            name: "VSSwiftSyntax",
            dependencies: [
                "VSSwiftCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftSyntaxTests",
            dependencies: ["VSSwiftSyntax", "VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
