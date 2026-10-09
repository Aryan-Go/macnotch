// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacNotch", targets: ["MacNotch"])
    ],
    targets: [
        .executableTarget(
            name: "MacNotch",
            path: "Sources/MacNotch",
            resources: [
                .copy("Resources/mediaremote-adapter.pl"),
                .copy("Resources/MediaRemoteAdapter.framework"),
                .copy("Resources/MediaRemoteAdapter.LICENSE")
            ]
        )
    ]
)
