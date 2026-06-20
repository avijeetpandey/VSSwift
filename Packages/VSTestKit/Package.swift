// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSTestKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VSTestKit", targets: ["VSTestKit"])
    ],
    targets: [
        .target(name: "VSTestKit", swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
