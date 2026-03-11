import SwiftUI
import SwiftData

@main
struct VoiceNativeApp: App {
    @State private var appState = AppState()
    @State private var showOnboarding = false

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

                    appState.permissions.checkAllPermissions()
                    if !appState.permissions.allPermissionsGranted {
                        showOnboarding = true
                    }

                    await appState.initialize()
                }
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolEffect(.pulse, isActive: appState.isIconAnimating && appState.phase == .listening)
                .symbolEffect(.variableColor.iterative, isActive: appState.isIconAnimating && appState.phase == .processing)
                .symbolEffect(.pulse, isActive: appState.isIconAnimating && appState.phase == .modelLoading)
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

        Window("Setup", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}
