// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ResourceBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ResourceBar", targets: ["ResourceBar"]),
        .executable(name: "DisplayBar", targets: ["DisplayBar"])
    ],
    targets: [
        .target(
            name: "CMetrics",
            path: "Sources/CMetrics"
        ),
        .executableTarget(
            name: "ResourceBar",
            dependencies: ["CMetrics"],
            path: "Sources/ResourceBar",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "DisplayBar",
            dependencies: ["CMetrics"],
            path: "Sources/DisplayBar",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreImage"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
