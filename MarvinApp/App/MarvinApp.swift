import SwiftUI

@main
struct MarvinApp: App {
    @StateObject private var manager = ConversationManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Inactive includes permission prompts and the lock transition.
                    if phase == .background { manager.setBackgrounded(true) }
                    else if phase == .active { manager.setBackgrounded(false) }
                }
        }
    }
}
