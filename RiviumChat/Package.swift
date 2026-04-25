// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RiviumChat",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "RiviumChat",
            targets: ["RiviumChat"]
        ),
    ],
    dependencies: [
        // Centrifuge Swift client for Centrifugo
        .package(url: "https://github.com/centrifugal/centrifuge-swift.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "RiviumChat",
            dependencies: [
                .product(name: "SwiftCentrifuge", package: "centrifuge-swift"),
            ],
            path: "Sources/RiviumChat"
        ),
        .testTarget(
            name: "RiviumChatTests",
            dependencies: ["RiviumChat"],
            path: "Tests/RiviumChatTests"
        ),
    ]
)
