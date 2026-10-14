// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "13YearsClockKit",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "ThirteenYearsClockKit", targets: ["ThirteenYearsClockKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "ThirteenYearsClockKit",
            dependencies: [
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            resources: [.copy("Resources/WebPager")]
        ),
    ]
)
