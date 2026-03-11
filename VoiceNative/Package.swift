// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceNative",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "VoiceNative", targets: ["VoiceNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceNative",
            dependencies: ["WhisperKit"],
            path: "Sources/VoiceNative",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)
