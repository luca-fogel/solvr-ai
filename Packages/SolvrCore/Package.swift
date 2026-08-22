// swift-tools-version: 6.0
import PackageDescription

// The parts of solvr.ai that are pure text handling, split out so they can be
// tested in two seconds with no Xcode, no simulator and no API key. Everything
// here is Foundation-only on purpose: the moment this imports UIKit, it stops
// being runnable by `swift test` and the tests stop getting run.
//
// The providers live here for a related reason: the evaluation harness has to
// measure the code the app actually runs, and a harness with its own HTTP client
// would be measuring a second implementation while reporting the numbers as if
// they came from the first.
let package = Package(
    name: "SolvrCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SolvrCore", targets: ["SolvrCore"]),
        .executable(name: "solvr-eval", targets: ["solvr-eval"]),
        .executable(name: "solvr-distill", targets: ["solvr-distill"]),
    ],
    targets: [
        .target(name: "SolvrCore"),
        .executableTarget(
            name: "solvr-eval",
            dependencies: ["SolvrCore"],
            resources: [.copy("problems.json")]),
        .executableTarget(name: "solvr-distill", dependencies: ["SolvrCore"]),
        .testTarget(name: "SolvrCoreTests", dependencies: ["SolvrCore"]),
    ]
)
