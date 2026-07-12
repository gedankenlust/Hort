// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hort",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hort", targets: ["Hort"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .executableTarget(
            name: "Hort",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: ".",
            exclude: [
                "README.md",
                "CHANGELOG.md",
                "CONTRIBUTING.md",
                "LICENSE",
                "ROADMAP.md",
                "SECURITY.md",
                "Assets",
                "Scripts",
                "Tests",
                "dist",
                "Docs",
                "Specs"
            ],
            sources: [
                "App",
                "Core",
                "UI",
                "Database",
                "Services",
                "Export",
                "AI"
            ],
            resources: [
                .copy("Assets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HortTests",
            dependencies: ["Hort"],
            path: "Tests"
        )
    ]
)
