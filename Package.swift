// swift-tools-version: 6.0
import PackageDescription

// Platform minimums are placeholders: confirm against current Xcode/macOS before release.
let package = Package(
    name: "WidgetProCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(
            name: "WidgetProCore",
            targets: ["WidgetSpec", "WidgetExpr", "WidgetData", "WidgetRender"]
        )
    ],
    targets: [
        .target(name: "WidgetSpec"),
        .target(name: "WidgetExpr"),
        .target(name: "WidgetData", dependencies: ["WidgetSpec", "WidgetExpr"]),
        .target(name: "WidgetRender", dependencies: ["WidgetSpec", "WidgetExpr", "WidgetData"]),
        .testTarget(name: "WidgetSpecTests", dependencies: ["WidgetSpec"])
    ]
)
