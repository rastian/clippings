// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ClippingsCore", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "ClippingsCore", targets: ["ClippingsCore"])],
    targets: [.target(name: "ClippingsCore"), .testTarget(name: "ClippingsCoreTests", dependencies: ["ClippingsCore"])],
    swiftLanguageModes: [.v6]
)
