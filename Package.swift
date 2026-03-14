// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskPins",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeskPinsAppSupport", targets: ["DeskPinsAppSupport"]),
        .library(name: "DeskPinsAccessibility", targets: ["DeskPinsAccessibility"]),
        .library(name: "DeskPinsWindowCatalog", targets: ["DeskPinsWindowCatalog"]),
        .library(name: "DeskPinsOverlay", targets: ["DeskPinsOverlay"]),
        .library(name: "DeskPinsPinned", targets: ["DeskPinsPinned"]),
        .library(name: "DeskPinsHotKey", targets: ["DeskPinsHotKey"]),
        .library(name: "DeskPinsPinning", targets: ["DeskPinsPinning"]),
        .executable(name: "DeskPinsMenuBarApp", targets: ["DeskPinsMenuBarApp"]),
        .executable(name: "DeskPinsAppSupportSmokeTests", targets: ["DeskPinsAppSupportSmokeTests"]),
        .executable(name: "DeskPinsPinnedSmokeTests", targets: ["DeskPinsPinnedSmokeTests"]),
        .executable(
            name: "DeskPinsPinnedPersistenceSmokeTests",
            targets: ["DeskPinsPinnedPersistenceSmokeTests"]
        ),
        .executable(name: "DeskPinsWindowCatalogSmokeTests", targets: ["DeskPinsWindowCatalogSmokeTests"]),
        .executable(name: "DeskPinsAccessibilitySmokeTests", targets: ["DeskPinsAccessibilitySmokeTests"]),
        .executable(name: "DeskPinsPinningSmokeTests", targets: ["DeskPinsPinningSmokeTests"])
    ],
    targets: [
        .target(
            name: "DeskPinsAppSupport",
            dependencies: [
                "DeskPinsAccessibility",
                "DeskPinsPinning",
                "DeskPinsPinned",
                "DeskPinsWindowCatalog"
            ],
            path: "App/Support"
        ),
        .target(
            name: "DeskPinsAccessibility",
            dependencies: ["DeskPinsPinned"],
            path: "Core/Accessibility"
        ),
        .target(
            name: "DeskPinsWindowCatalog",
            dependencies: ["DeskPinsPinned"],
            path: "Core/WindowCatalog"
        ),
        .target(
            name: "DeskPinsOverlay",
            path: "Core/Overlay"
        ),
        .target(
            name: "DeskPinsPinned",
            path: "Core/Pinned"
        ),
        .target(
            name: "DeskPinsHotKey",
            path: "Core/HotKey"
        ),
        .target(
            name: "DeskPinsPinning",
            dependencies: ["DeskPinsAccessibility", "DeskPinsPinned", "DeskPinsWindowCatalog"],
            path: "Core/Pinning"
        ),
        .executableTarget(
            name: "DeskPinsMenuBarApp",
            dependencies: ["DeskPinsAppSupport"],
            path: "App/MenuBarApp"
        ),
        .executableTarget(
            name: "DeskPinsAppSupportSmokeTests",
            dependencies: ["DeskPinsAppSupport"],
            path: "Tools/DeskPinsAppSupportSmokeTests"
        ),
        .executableTarget(
            name: "DeskPinsPinnedSmokeTests",
            dependencies: ["DeskPinsPinned"],
            path: "Tools/DeskPinsPinnedSmokeTests"
        ),
        .executableTarget(
            name: "DeskPinsPinnedPersistenceSmokeTests",
            dependencies: ["DeskPinsPinned"],
            path: "Tools/DeskPinsPinnedPersistenceSmokeTests"
        ),
        .executableTarget(
            name: "DeskPinsWindowCatalogSmokeTests",
            dependencies: ["DeskPinsWindowCatalog"],
            path: "Tools/DeskPinsWindowCatalogSmokeTests"
        ),
        .executableTarget(
            name: "DeskPinsAccessibilitySmokeTests",
            dependencies: ["DeskPinsAccessibility", "DeskPinsPinned"],
            path: "Tools/DeskPinsAccessibilitySmokeTests"
        ),
        .executableTarget(
            name: "DeskPinsPinningSmokeTests",
            dependencies: ["DeskPinsPinning", "DeskPinsPinned", "DeskPinsWindowCatalog"],
            path: "Tools/DeskPinsPinningSmokeTests"
        )
    ]
)
