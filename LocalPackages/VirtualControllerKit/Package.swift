// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VirtualControllerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VirtualControllerKit", targets: ["VirtualControllerKit"]),
        // iOS-only SwiftUI/UIKit controls; compiles to nothing on other platforms.
        .library(name: "VirtualControllerUI", targets: ["VirtualControllerUI"]),
    ],
    targets: [
        .target(name: "VirtualControllerKit"),
        .target(name: "VirtualControllerUI", dependencies: ["VirtualControllerKit"]),
        .testTarget(name: "VirtualControllerKitTests", dependencies: ["VirtualControllerKit"]),
    ]
)
