// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CupcakeKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CupcakeModels", targets: ["CupcakeModels"]),
        .library(name: "CupcakeNetworking", targets: ["CupcakeNetworking"]),
        .library(name: "CupcakeAuth", targets: ["CupcakeAuth"]),
        .library(name: "CupcakeSync", targets: ["CupcakeSync"]),
        .library(name: "CupcakeOntology", targets: ["CupcakeOntology"]),
        .library(name: "CupcakeTranscription", targets: ["CupcakeTranscription"]),
    ],
    targets: [
        // Foundation + SwiftData only. No networking, no UI.
        .target(name: "CupcakeModels"),

        // Pure DTOs + endpoint constants. No SwiftData, no UI.
        .target(name: "CupcakeNetworking"),

        // JWT bootstrap -> DeviceToken exchange, Keychain wrapper.
        .target(
            name: "CupcakeAuth",
            dependencies: ["CupcakeNetworking"]
        ),

        // Outbox engine, delta-sync, deletion-feed consumption, DTO<->@Model mapping.
        .target(
            name: "CupcakeSync",
            dependencies: ["CupcakeModels", "CupcakeNetworking", "CupcakeAuth"]
        ),

        // GitHub releases manifest fetch, per-table sqlite.gz import, SDRF column list.
        .target(
            name: "CupcakeOntology",
            dependencies: ["CupcakeModels"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        // Speech/Translation wrappers, WebVTT formatting.
        .target(
            name: "CupcakeTranscription",
            dependencies: ["CupcakeModels"]
        ),

        .testTarget(
            name: "CupcakeNetworkingTests",
            dependencies: ["CupcakeNetworking"]
        ),
        .testTarget(
            name: "CupcakeSyncTests",
            dependencies: ["CupcakeSync"]
        ),
        .testTarget(
            name: "CupcakeAuthTests",
            dependencies: ["CupcakeAuth"]
        ),
        .testTarget(
            name: "CupcakeOntologyTests",
            dependencies: ["CupcakeOntology"]
        ),
        .testTarget(
            name: "CupcakeTranscriptionTests",
            dependencies: ["CupcakeTranscription"]
        ),
    ]
)
