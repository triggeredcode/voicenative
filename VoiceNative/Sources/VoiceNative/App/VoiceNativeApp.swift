import SwiftUI
import SwiftData

@main
struct VoiceNativeApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
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
    }
}
