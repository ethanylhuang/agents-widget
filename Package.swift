// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agents-widget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agents-widget", targets: ["AgentsWidgetApp"])
    ],
    targets: [
        .target(
            name: "AgentsWidgetCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "AgentsWidgetApp",
            dependencies: ["AgentsWidgetCore"]
        ),
        .testTarget(
            name: "AgentsWidgetTests",
            dependencies: ["AgentsWidgetCore"]
        )
    ]
)
