// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rivium-chat-ios-sdk",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "RiviumChat",
            targets: ["RiviumChat"]
        ),
        .library(
            name: "RiviumChatUI",
            targets: ["RiviumChatUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/centrifugal/centrifuge-swift.git", from: "0.5.0"),
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "RiviumChat",
            dependencies: [
                .product(name: "SwiftCentrifuge", package: "centrifuge-swift"),
            ],
            path: "RiviumChat/Sources/RiviumChat"
        ),
        .target(
            name: "RiviumChatUI",
            dependencies: [
                "RiviumChat",
                "SDWebImageSwiftUI",
            ],
            path: "RiviumChatUI/Sources/RiviumChatUI"
        ),
    ]
)
