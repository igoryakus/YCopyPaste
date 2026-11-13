// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YCopyPaste",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YCopyPaste",
            path: "Sources/YCopyPaste",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
