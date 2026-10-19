// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictationMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DictationMenu", targets: ["DictationMenu"])
    ],
    targets: [
        .executableTarget(
            name: "DictationMenu",
            path: "Sources/DictationMenu",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
