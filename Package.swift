// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vault",
    platforms: [.macOS(.v14)],   // @Observable 需要 macOS 14 以上
    targets: [
        .executableTarget(name: "Vault", path: "Sources/Vault")
    ]
)
