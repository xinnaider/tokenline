// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenlineWidgetKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TokenlineWidgetKit", targets: ["TokenlineWidgetKit"])],
    targets: [
        .target(name: "TokenlineWidgetKit"),
        .testTarget(name: "TokenlineWidgetKitTests", dependencies: ["TokenlineWidgetKit"]),
    ]
)
