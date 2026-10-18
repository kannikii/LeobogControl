// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LeobogControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LeobogControl", targets: ["LeobogControl"]),
        .executable(name: "leobog-cli", targets: ["leobog-cli"]),
        .library(name: "LeobogCore", targets: ["LeobogCore"]),
    ],
    targets: [
        .target(
            name: "LeobogCore",
            path: "Sources/LeobogCore",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "LeobogControl",
            dependencies: ["LeobogCore"],
            path: "Sources/LeobogControl",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),
        .executableTarget(
            name: "leobog-cli",
            dependencies: ["LeobogCore"],
            path: "Sources/leobog-cli"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
