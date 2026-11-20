// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LimpezaMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LimpezaMac", targets: ["LimpezaMac"])
    ],
    targets: [
        .executableTarget(
            name: "LimpezaMac",
            path: "Sources/LimpezaMac"
        )
    ]
)
