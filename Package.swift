// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "SEC Filing Sniper",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "SEC Filing Sniper",
            targets: ["AppModule"],
            bundleIdentifier: "com.cbogdanmihai.SECFilingSniper",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [.landscapeLeft, .landscapeRight, .portrait]
        )
    ],
    targets: [
        .executableTarget(name: "AppModule", path: "App")
    ]
)
