// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActionsTray",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ActionsTray", path: "Sources/ActionsTray")
    ]
)
