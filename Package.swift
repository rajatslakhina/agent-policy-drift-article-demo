// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PolicyCanary",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PolicyCanary", targets: ["PolicyCanary"]),
    ],
    targets: [
        .target(name: "PolicyCanary"),
        .testTarget(name: "PolicyCanaryTests", dependencies: ["PolicyCanary"]),
    ]
)
