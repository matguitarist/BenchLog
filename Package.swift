// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BenchLog",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.5.0"),
        // SQLite: a plain, documented schema that a future iOS app, Android app, or sync server can share.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
    ],
    targets: [
        // Data and rules with no SwiftUI or AppKit, so tests run without the app
        // and a future iPhone/iPad app can use the same code.
        .target(name: "BenchLogKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // Boardview files (.brd, BRD2, .bdv) and the rules that link a board to its schematic. Foundation only,
        // so a standalone viewer or the iPhone/iPad app can use it as is.
        .target(name: "BoardViewKit"),
        // The sync server built into the app: the same API and data folder as server/ (Node).
        .target(name: "BenchLogServerKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // Contents/MacOS/BenchLogServer: runs it, from Terminal or as the "Use This Mac as the Server" login item.
        .executableTarget(name: "BenchLogServer", dependencies: ["BenchLogServerKit"]),
        .executableTarget(
            name: "BenchLog",
            dependencies: ["BenchLogKit", "BoardViewKit", "BenchLogServerKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit")],
            // BenchLog Help: Help/<language>/<topic>.md, read through Bundle.module.
            resources: [.copy("Help/en"), .copy("Help/fr")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "BenchLogKitTests", dependencies: ["BenchLogKit", "BoardViewKit", "BenchLogServerKit", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
