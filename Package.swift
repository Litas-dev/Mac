// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kivana",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Kivana", targets: ["PersonalFinancesApp"])
    ],
    targets: [
        .executableTarget(
            name: "PersonalFinancesApp",
            path: "Sources/PersonalFinancesApp",
            exclude: ["Info.plist", "Entitlements.mac.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .testTarget(
            name: "Tests",
            dependencies: ["PersonalFinancesApp"],
            path: "Tests"
        )
    ]
)
