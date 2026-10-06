// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarvinCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MarvinCore", targets: ["MarvinCore"])],
    targets: [
        .target(name: "MarvinCore", path: "MarvinApp",
                exclude: ["App", "Audio", "Speech", "TTS", "Views", "Security", "Resources",
                          "Conversation/ConversationManager.swift", "Conversation/RealtimeConversation.swift"],
                sources: ["AI", "Models", "Configuration", "Conversation/ConversationContext.swift"]),
        .testTarget(name: "MarvinCoreTests", dependencies: ["MarvinCore"])
    ]
)
