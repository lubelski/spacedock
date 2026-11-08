// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Spacedock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        // Pinned to our fork while the window-action delegate is under review (lubelski/libghostty-spm PR 1).
        // Return to Lakr233/libghostty-spm from: the first release that carries it.
        .package(url: "https://github.com/lubelski/libghostty-spm.git", branch: "window-action-delegate"),
    ],
    targets: [
        .executableTarget(
            name: "Spacedock",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ],
            path: "Sources/Spacedock"
        ),
    ]
)
