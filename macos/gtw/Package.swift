// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gtw",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkbenchProtocol", targets: ["WorkbenchProtocol"]),
        .executable(name: "gtw", targets: ["gtw"]),
    ],
    targets: [
        .target(name: "WorkbenchProtocol"),
        .target(name: "GtwCore", dependencies: ["WorkbenchProtocol"]),
        .executableTarget(name: "gtw", dependencies: ["GtwCore", "WorkbenchProtocol"]),
        .testTarget(name: "WorkbenchProtocolTests", dependencies: ["WorkbenchProtocol"]),
        .testTarget(name: "GtwCoreTests", dependencies: ["GtwCore", "WorkbenchProtocol"]),
    ]
)
