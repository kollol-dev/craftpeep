// swift-tools-version: 6.0
// The app's only use of Sparkle. Kept out of CraftPeepKit so the core packages stay free of it and
// buildable for iPhone; the app links this product on macOS.
import PackageDescription

let package = Package(
    name: "CraftPeepUpdater",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CraftPeepUpdater", targets: ["Updater"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "Updater", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
    ]
)
