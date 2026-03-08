// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lino",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lino",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources/Lino",
            exclude: ["Resources/Info.plist"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "LinoTests",
            dependencies: [
                "Lino",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/LinoTests"
        ),
    ]
)
