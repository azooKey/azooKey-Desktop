// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(macOS)
let kanaKanjiConverterTraits: Set<Package.Dependency.Trait> = ["Zenzai"]
#else
// for testing in Ubuntu environment.
let kanaKanjiConverterTraits: Set<Package.Dependency.Trait> = []
#endif

var products: [Product] = [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
        name: "Core",
        targets: ["Core"]
    )
]

var targets: [Target] = [
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
            .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation")
        ],
        resources: [.copy("Resources/postal-addresses.tsv")],
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

#if os(macOS)
products.append(
    .executable(
        name: "ConverterServer",
        targets: ["ConverterServer"]
    )
)
targets.append(
    .executableTarget(
        name: "ConverterServer",
        dependencies: ["Core"],
        swiftSettings: [.interoperabilityMode(.Cxx)]
    )
)
#endif

let package = Package(
    name: "Core",
    platforms: [.macOS(.v13)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "67ec8e68d17a534b5b9929b920995ef3811e89fe", traits: kanaKanjiConverterTraits),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: targets
)
