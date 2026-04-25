// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RiviumChatEcommerce",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "RiviumChatEcommerce",
            targets: ["RiviumChatEcommerce"]
        )
    ],
    dependencies: [
        .package(path: "../RiviumChat"),
        .package(path: "../RiviumChatUI"),
        .package(url: "https://github.com/Rivium-co/rivium-push-ios-sdk.git", from: "0.1.3")
    ],
    targets: [
        .target(
            name: "RiviumChatEcommerce",
            dependencies: ["RiviumChat", "RiviumChatUI", "RiviumPush"],
            path: "RiviumChatEcommerce"
        )
    ]
)
