// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CharadesCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CharadesCore", targets: ["CharadesCore"])],
    targets: [
        .target(name: "CharadesCore", path: "Sources/Core", resources: [.process("Resources")]),
        .testTarget(name: "CharadesCoreTests", dependencies: ["CharadesCore"], path: "Tests/CharadesCoreTests")
    ]
)
