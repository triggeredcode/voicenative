import SwiftUI
import SwiftData

@main
struct VoiceNativeApp: App {
    @State private var appState = AppState()
    
    private let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try ModelContainer(for: TranscriptionRecord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
                .modelContainer(modelContainer)
                .task {
                    appState.setModelContext(modelContainer.mainContext)
                    await appState.initialize()
                }
        } label: {
            Label {
                Text("VoiceNative")
            } icon: {
                Image(systemName: appState.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        Window("History", id: "history") {
            HistoryView()
                .modelContainer(modelContainer)
        }
    }
}
