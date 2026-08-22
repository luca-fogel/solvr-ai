// swift-tools-version: 6.0
import PackageDescription

// The parts of solvr.ai that are pure text handling, split out so they can be
// tested in two seconds with no Xcode, no simulator and no API key. Everything
// here is Foundation-only on purpose: the moment this imports UIKit, it stops
// being runnable by `swift test` and the tests stop getting run.
let package = Package(
    name: "SolvrCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SolvrCore", targets: ["SolvrCore"]),
    ],
    targets: [
        .target(name: "SolvrCore"),
        .testTarget(name: "SolvrCoreTests", dependencies: ["SolvrCore"]),
    ]
)
