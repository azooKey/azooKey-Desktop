// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if canImport(FoundationModels)
let isXcodeVersion26 = true
#else
let isXcodeVersion26 = false
#endif

let xcode26AdditionalTargets: [Target] = [
    .binaryTarget(
        // Note: Xcode 26以降、AzooKeyKanaKanjiConverter側のXCFrameworkのbinaryTargetをXcodeが解決してくれなくなった。
        // そこで、binaryTargetを再度AzooKeyCore側でも要求することで、結果的に認識されるようになる。
        // さらに`AzooKeyUtils`でも`llama`を要求しないとビルドは通らない。
        // ただし、Xcode 26より前の場合は逆にこの対応を入れると動作しないので、Xcodeバージョンを確認する必要がある
        name: "llama",
        url: "https://github.com/azooKey/llama.cpp/releases/download/b4846/signed-llama.xcframework.zip",
        // this can be computed `swift package compute-checksum llama-b4844-xcframework.zip`
        checksum: "db3b13169df8870375f212e6ac21194225f1c85f7911d595ab64c8c790068e0a"
    )
]

let xcode26AdditionalTargetDependency: [Target.Dependency] = [
    "llama"
]

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
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "40998e7a25160fb89af690780447629b740fb83b", traits: ["Zenzai"])
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
            ] + (isXcodeVersion26 ? xcode26AdditionalTargetDependency : []),
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
    ] + (isXcodeVersion26 ? xcode26AdditionalTargets : [])
)
