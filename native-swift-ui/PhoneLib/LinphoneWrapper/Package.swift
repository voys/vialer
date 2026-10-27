// swift-tools-version:5.9

import PackageDescription

// Kept as its own module so the `LinphoneCall` alias resolves to linphonesw's `Call`
// rather than the phone lib's own `Call` struct.
let package = Package(
    name: "LinphoneWrapper",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LinphoneWrapper", targets: ["LinphoneWrapper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/BelledonneCommunications/linphone-sdk-swift-ios.git", exact: "5.4.24"),
    ],
    targets: [
        .target(
            name: "LinphoneWrapper",
            dependencies: [
                .product(name: "linphonesw", package: "linphone-sdk-swift-ios"),
            ],
            path: "Sources"
        ),
    ]
)
