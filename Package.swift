// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AIUsageMonitor", targets: ["AIUsageMonitor"])],
    targets: [.executableTarget(name: "AIUsageMonitor")]
)
