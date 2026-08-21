// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownReader",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownReader",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/MarkdownReader"
        ),
    ]
)
