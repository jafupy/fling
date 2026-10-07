// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlingWM",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlingWM", targets: ["FlingWM"])
    ],
    targets: [
        .target(
            name: "CMultitouchShim",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "FlingWM",
            dependencies: ["CMultitouchShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
