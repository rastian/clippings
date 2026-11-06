// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LinkinCore", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "LinkinCore", targets: ["LinkinCore"])],
    targets: [.target(name: "LinkinCore"), .testTarget(name: "LinkinCoreTests", dependencies: ["LinkinCore"])],
    swiftLanguageModes: [.v6]
)
