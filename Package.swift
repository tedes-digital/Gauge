// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gauge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Gauge", targets: ["Gauge"])],
    targets: [.executableTarget(name: "Gauge")]
)
