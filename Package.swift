// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ductura",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Ductura", targets: ["Ductura"]),
        .library(name: "DucturaCore", targets: ["DucturaCore"]),
    ],
    targets: [
        .target(name: "DucturaCore"),
        .executableTarget(name: "Ductura", dependencies: ["DucturaCore"]),
        .testTarget(name: "DucturaCoreTests", dependencies: ["DucturaCore"]),
    ]
)
