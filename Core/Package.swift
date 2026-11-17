// swift-tools-version: 6.0
// DaysCore: the rules, Foundation only, so it tests on Linux. No SwiftUI, no SwiftData.
import PackageDescription

let package = Package(
    name: "DaysCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "DaysCore", targets: ["DaysCore"])],
    targets: [
        .target(name: "DaysCore"),
        .testTarget(name: "DaysCoreTests", dependencies: ["DaysCore"]),
    ]
)
