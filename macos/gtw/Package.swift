// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gtw",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkbenchProtocol", targets: ["WorkbenchProtocol"]),
    ],
    targets: [
        .target(name: "WorkbenchProtocol"),
        .testTarget(name: "WorkbenchProtocolTests", dependencies: ["WorkbenchProtocol"]),
    ]
)
