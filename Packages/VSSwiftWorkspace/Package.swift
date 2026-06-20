// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftWorkspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftWorkspace", targets: ["VSSwiftWorkspace"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSTestKit")
    ],
    targets: [
        .target(
            name: "VSSwiftWorkspace",
            dependencies: ["VSSwiftCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftWorkspaceTests",
            dependencies: ["VSSwiftWorkspace", "VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
