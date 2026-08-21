// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MemWatch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MemWatch",
            targets: ["MemWatch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MemWatch",
            path: ".",
            sources: [
                "MemWatchApp.swift",
                "Models",
                "Collectors",
                "Services",
                "Views"
            ]
        )
    ]
)
