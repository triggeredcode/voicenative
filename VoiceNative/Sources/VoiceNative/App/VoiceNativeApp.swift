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
        } label: {
            MenuBarLabel(appState: appState)
                .task {
                    guard !appState.hasBootstrapped else { return }
                    appState.setModelContext(modelContainer.mainContext, container: modelContainer)
                    await appState.initialize()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Setup", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Menu Bar Label (SF Symbols only -- custom shapes don't render here)

struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        Group {
            switch appState.iconFeedback {
            case .copied:
                Image(systemName: "checkmark.circle.fill")
            case .noSpeech:
                Image(systemName: "mic.slash")
            case .cancelled:
                Image(systemName: "xmark.circle")
            case .none:
                phaseIcon
            }
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch appState.phase {
        case .listening:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative.reversing, isActive: true)
        case .processing:
            Image(systemName: "ellipsis.circle")
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .modelLoading:
            Image(systemName: "arrow.down.circle")
                .symbolEffect(.pulse, isActive: true)
        case .ready:
            Image(systemName: "mic")
        case .idle:
            Image(systemName: "mic")
                .symbolEffect(.pulse, isActive: true)
        case .error:
            Image(systemName: "exclamationmark.triangle")
        }
    }
}
