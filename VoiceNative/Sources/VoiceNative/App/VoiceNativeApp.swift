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
                .onAppear {
                    // Only bootstrap once -- onAppear also fires per-open but initialize() guards internally
                    if !appState.hasBootstrapped {
                        appState.setModelContext(modelContainer.mainContext)
                        Task { await appState.initialize() }
                    }
                }
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolEffect(.pulse, isActive: appState.isIconAnimating && appState.phase == .listening)
                .symbolEffect(.variableColor.iterative, isActive: appState.isIconAnimating && appState.phase == .processing)
                .symbolEffect(.pulse, isActive: appState.isIconAnimating && appState.phase == .modelLoading)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)

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
