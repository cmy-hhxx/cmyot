// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Syntax",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "Syntax", targets: [
            "SyntaxFormat",
            "SyntaxParsers",
        ]),
        .library(name: "SyntaxFormat", targets: ["SyntaxFormat"]),
        .library(name: "SyntaxParsers", targets: ["SyntaxParsers"]),
    ],
    dependencies: [
        .package(name: "EditorCore", path: "../EditorCore"),
        
        .package(url: "https://github.com/apple/swift-argument-parser", from: Version(1, 7, 0)),
        .package(url: "https://github.com/jpsim/Yams", from: Version(6, 2, 0)),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: Version(0, 62, 0)),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: Version(0, 10, 0)),
        
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: Version(0, 25, 1)),
        .package(url: "https://github.com/1024jp/tree-sitter-javascript", branch: "swiftPackage"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", from: Version(0, 5, 3)),
        .package(url: "https://github.com/1024jp/tree-sitter-python", branch: "swiftPackage"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: Version(0, 23, 2)),
    ],
    targets: [
        .target(
            name: "SyntaxFormat",
            dependencies: ["EditorCore", "Yams"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SyntaxFormatTests",
            dependencies: ["SyntaxFormat", "EditorCore"],
            resources: [.copy("Syntaxes")]
        ),
        
        .target(
            name: "SyntaxParsers",
            dependencies: [
                "EditorCore",
                "SyntaxFormat",
                .product(name: "SwiftTreeSitterLayer", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
            ],
            resources: [.copy("Queries")]
        ),
        .testTarget(
            name: "SyntaxParsersTests",
            dependencies: ["SyntaxParsers", "EditorCore"],
            resources: [.copy("Samples")]
        ),
        
        .executableTarget(
            name: "SyntaxMapBuilder",
            dependencies: [
                "SyntaxFormat",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
    
        .executableTarget(
            name: "SyntaxMigrator",
            dependencies: [
                "SyntaxFormat",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
    ],
    swiftLanguageModes: [.v6]
)


for target in package.targets {
    target.plugins = (target.plugins ?? []) + [
        .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]
}
