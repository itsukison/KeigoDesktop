// swift-tools-version:5.9
import PackageDescription

// The testable core. Deliberately free of AppKit so capture/replace and the
// service layer can be exercised without a window server. `TextIO` imports
// ApplicationServices (where AXUIElement lives) but nothing above it.
let package = Package(
    name: "KeigoButtonMacCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesktopRewriteKit", targets: ["DesktopRewriteKit"]),
        .library(name: "TextIO", targets: ["TextIO"]),
    ],
    targets: [
        .target(name: "DesktopRewriteKit"),
        .target(name: "TextIO", dependencies: ["DesktopRewriteKit"]),
        .testTarget(name: "DesktopRewriteKitTests", dependencies: ["DesktopRewriteKit"]),
        .testTarget(name: "TextIOTests", dependencies: ["TextIO"]),
    ]
)
