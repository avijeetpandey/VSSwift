// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSSwift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VSSwift", targets: ["VSSwiftApp"])
    ],
    dependencies: [
        .package(path: "Packages/VSSwiftUI")
    ],
    targets: [
        .executableTarget(
            name: "VSSwiftApp",
            dependencies: [
                .product(name: "VSSwiftUI", package: "VSSwiftUI")
            ],
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/VSSwift.icns"),
                .copy("Resources/Assets.xcassets")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
