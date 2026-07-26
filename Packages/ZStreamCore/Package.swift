// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZStreamCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZStreamCore", targets: ["ZStreamCore"]),
    ],
    targets: [
        .target(name: "ZStreamCore"),
    ],
    swiftLanguageModes: [.v5]
)
