// swift-tools-version: 6.1

import PackageDescription

var products: [Product] = []
var targets: [Target] = [
    .target(name: "pdisasm", dependencies: []),
    .executableTarget(
        name: "pdisasm-cli",
        dependencies: ["pdisasm"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
        name: "pdisasmTests",
        dependencies: ["pdisasm"],
        resources: [.copy("Fixtures")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

#if os(macOS)
products.append(.library(name: "pdisasm-gui-lib", targets: ["pdisasm-gui-lib"]))
targets.append(contentsOf: [
    .target(
        name: "pdisasm-gui-lib",
        dependencies: ["pdisasm"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
        name: "pdisasm-gui",
        dependencies: ["pdisasm-gui-lib"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
])
#endif

let package = Package(
    name: "pdisasm",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [],
    targets: targets,
    swiftLanguageModes: [.v6]
)
