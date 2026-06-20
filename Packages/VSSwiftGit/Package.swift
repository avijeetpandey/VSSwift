// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftGit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSSwiftGit", targets: ["VSSwiftGit"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSTestKit")
    ],
    targets: [
        .target(
            name: "VSSwiftGit",
            dependencies: ["VSSwiftCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VSSwiftGitTests",
            dependencies: ["VSSwiftGit", "VSSwiftCore", .product(name: "VSTestKit", package: "VSTestKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
