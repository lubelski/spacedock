// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Spacedock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "2.2.2026110702"),
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
