// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CraftPeepKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(
            name: "CraftPeepKit",
            targets: [
                "Domain", "Persistence", "Ingestion", "Intelligence", "AI",
                "WidgetSpec", "WidgetExpr", "WidgetRuntime", "WidgetRender"
            ]
        )
    ],
    dependencies: [
        // The only third-party dependency (ADR-002). Pinned exactly; review before bumping.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0")
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "Persistence",
            dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "Ingestion",
            dependencies: ["Domain"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "Intelligence",
            dependencies: ["Domain"],
            resources: [.process("Resources")]
        ),
        .target(name: "AI", dependencies: ["Domain"]),
        .target(name: "WidgetSpec"),
        .target(name: "WidgetExpr"),
        .target(name: "WidgetRuntime", dependencies: ["WidgetSpec", "WidgetExpr"]),
        .target(name: "WidgetRender", dependencies: ["WidgetSpec", "WidgetExpr", "WidgetRuntime"]),
        .testTarget(name: "WidgetExprTests", dependencies: ["WidgetExpr"]),
        .testTarget(name: "WidgetSpecTests", dependencies: ["WidgetSpec"]),
        .testTarget(
            name: "IngestionTests",
            dependencies: ["Ingestion", "Persistence", "Domain"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain"]),
        .testTarget(
            name: "AITests",
            dependencies: ["AI", "Intelligence", "Persistence", "Domain", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "IntelligenceTests",
            dependencies: ["Intelligence", "Ingestion", "Persistence", "Domain"],
            resources: [.copy("Fixtures")]
        )
    ]
)
