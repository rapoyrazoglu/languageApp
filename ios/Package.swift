// swift-tools-version: 5.9
//
// PaktlyKit — Swift SDK for the Paktly language pack ecosystem.
//
// The library is registry-agnostic: point RegistryClient at api.paktly.dev
// or any compatible self-hosted registry. Pack content is consumed offline
// after download; AI / sync features are optional and gated by the host app.
import PackageDescription

let package = Package(
    name: "PaktlyKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PaktlyKit", targets: ["PaktlyKit"]),
    ],
    targets: [
        .target(
            name: "PaktlyKit",
            path: "Sources/PaktlyKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PaktlyKitTests",
            dependencies: ["PaktlyKit"],
            path: "Tests/PaktlyKitTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
