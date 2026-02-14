// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(macOS)
let kanaKanjiConverterTraits: Set<Package.Dependency.Trait> = ["Zenzai"]
#else
// for testing in Ubuntu environment.
let kanaKanjiConverterTraits: Set<Package.Dependency.Trait> = []
#endif

let package = Package(
    name: "Core",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Core",
            targets: ["Core"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "44429812ea2f6fe1b8a759dd994c6b29eafbc88f", traits: kanaKanjiConverterTraits)
    ],
    targets: [
        .executableTarget(
            name: "git-info-generator"
        ),
        .plugin(
            name: "GitInfoPlugin",
            capability: .buildTool(),
            dependencies: [.target(name: "git-info-generator")]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "SwiftUtils", package: "AzooKeyKanaKanjiConverter"),
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)],
            plugins: [
                .plugin(name: "GitInfoPlugin")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        )
    ]
)
