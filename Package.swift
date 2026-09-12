// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sill",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SillCore", targets: ["SillCore"]),
        .executable(name: "sill", targets: ["SillApp"]),
        .executable(name: "silltests", targets: ["silltests"]),
    ],
    targets: [
        .target(name: "SillCore"),
        .executableTarget(name: "SillApp", dependencies: ["SillCore"]),
        .executableTarget(name: "silltests", dependencies: ["SillCore"], path: "Tests/SillCoreTests"),
    ]
)
