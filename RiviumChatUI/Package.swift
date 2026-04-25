// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RiviumChatUI",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RiviumChatUI",
            targets: ["RiviumChatUI"]
        )
    ],
    dependencies: [
        .package(path: "../RiviumChat"),
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "RiviumChatUI",
            dependencies: [
                "RiviumChat",
                "SDWebImageSwiftUI"
            ],
            path: "Sources/RiviumChatUI"
        ),
        .testTarget(
            name: "RiviumChatUITests",
            dependencies: ["RiviumChatUI"],
            path: "Tests/RiviumChatUITests"
        )
    ]
)
