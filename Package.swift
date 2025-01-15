// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "DeepLinkNow",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "DeepLinkNow",
            targets: ["DeepLinkNow"]),
    ],
    targets: [
        .target(
            name: "DeepLinkNow",
            dependencies: []),
        .testTarget(
            name: "DeepLinkNowTests",
            dependencies: ["DeepLinkNow"]),
    ]
) 