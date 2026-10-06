// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToneReplicator",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ToneReplicator", targets: ["ToneReplicator"])],
    targets: [
        .target(name: "ToneCore", publicHeadersPath: "include"),
        .executableTarget(name: "ToneReplicator", dependencies: ["ToneCore"]),
        .testTarget(name: "ToneReplicatorTests", dependencies: ["ToneReplicator"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
