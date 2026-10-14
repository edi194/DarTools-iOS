// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DarToolsIOS",
    platforms: [
        .iOS("26.0"),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "DarToolsIOS",
            targets: ["DarToolsIOS"]
        ),
    ],
    targets: [
        .target(
            name: "DarToolsIOS"
        ),
    ]
)
