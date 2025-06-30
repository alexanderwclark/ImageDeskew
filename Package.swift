// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageDeskew",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "ImageDeskew", targets: ["ImageDeskew"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ImageDeskew",
            dependencies: [],
            path: "ImageDeskew",
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("PhotosUI"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage")
            ]
        ),
        .testTarget(
            name: "ImageDeskewTests",
            dependencies: ["ImageDeskew"],
            path: "ImageDeskewTests"
        )
    ]
)
