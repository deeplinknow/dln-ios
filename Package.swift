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
    dependencies: [],
    targets: [
        .target(
            name: "DeepLinkNow",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("CoreTelephony"),
                .linkedFramework("AdSupport")
            ]),
        .testTarget(
            name: "DeepLinkNowTests",
            dependencies: ["DeepLinkNow"]),
    ]
) 