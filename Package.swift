// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnuckledCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "KnuckledCore", targets: ["KnuckledCore"])
    ],
    targets: [
        .target(name: "KnuckledCore"),
        .testTarget(name: "KnuckledCoreTests", dependencies: ["KnuckledCore"]),
    ]
)
