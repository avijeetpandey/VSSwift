// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwiftUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VSSwiftUI", targets: ["VSSwiftUI"])
    ],
    dependencies: [
        .package(path: "../VSSwiftCore"),
        .package(path: "../VSSwiftEngine"),
        .package(path: "../VSSwiftLSP"),
        .package(path: "../VSSwiftSyntax"),
        .package(path: "../VSSwiftWorkspace"),
        .package(path: "../VSSwiftGit")
    ],
    targets: [
        .target(
            name: "VSSwiftUI",
            dependencies: [
                "VSSwiftCore", "VSSwiftEngine", "VSSwiftLSP", "VSSwiftSyntax", "VSSwiftWorkspace", "VSSwiftGit"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
