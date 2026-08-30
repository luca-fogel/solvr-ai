// swift-tools-version: 6.0
import PackageDescription

// The parts of solvr.ai that are pure text handling, split out so they can be
// tested in two seconds with no Xcode, no simulator and no API key. Everything
// here is Foundation-only on purpose: the moment this imports UIKit, it stops
// being runnable by `swift test` and the tests stop getting run.
//
// The provider lives here for a related reason: the evaluation harness has to
// measure the code the app actually runs, not a second implementation of it.
// Since the hosted and self-hosted backends were removed there is only one real
// provider left -- Apple's on-device model -- and no HTTP client anywhere.
let package = Package(
    name: "SolvrCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SolvrCore", targets: ["SolvrCore"]),
        .executable(name: "solvr-eval", targets: ["solvr-eval"]),
    ],
    targets: [
        // SOLVR_DEMO compiles in the fixture backend -- canned answers, no
        // model, no network -- which drives the screenshot tooling and gives the
        // evaluation harness a free arm. Debug only, and deliberately so: it
        // returns the same answer to every question, and an app that ships the
        // ability to do that ships the ability to be wrong in the one way a
        // student cannot detect. In Release the fixtures are not merely
        // unreachable, they are not in the binary.
        .target(name: "SolvrCore",
                swiftSettings: [.define("SOLVR_DEMO", .when(configuration: .debug))]),
        .executableTarget(
            name: "solvr-eval",
            dependencies: ["SolvrCore"],
            resources: [.copy("problems.json")],
            swiftSettings: [.define("SOLVR_DEMO", .when(configuration: .debug))]),
        .testTarget(name: "SolvrCoreTests", dependencies: ["SolvrCore"],
                    swiftSettings: [.define("SOLVR_DEMO", .when(configuration: .debug))]),
    ]
)
