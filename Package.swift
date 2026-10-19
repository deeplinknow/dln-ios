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
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation")
            ]),
        .testTarget(
            name: "DeepLinkNowTests",
            dependencies: ["DeepLinkNow"]),
    ]
)
