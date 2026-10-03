// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceNote",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "VoiceNote", path: "Sources/VoiceNote")
    ]
)
