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
                    appState.setModelContext(modelContainer.mainContext)
                    await appState.initialize()
                }
        }
        .menuBarExtraStyle(.window)

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

// MARK: - Menu Bar Label

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
            RecordingBarsView()
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

// MARK: - Recording Waveform Bars (shown in menu bar during recording)

struct RecordingBarsView: View {
    @State private var wavePhase: Double = 0
    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    private let barCount = 7

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .frame(width: 2, height: barHeight(for: i))
            }
        }
        .frame(width: 18, height: 16)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.08)) {
                wavePhase += 0.4
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let t = Double(index) / Double(barCount - 1)
        let wave1 = sin(wavePhase + t * .pi * 2) * 0.35
        let wave2 = sin(wavePhase * 1.4 + t * .pi * 3) * 0.25
        let combined = (wave1 + wave2 + 1.0) / 2.0
        return 3 + CGFloat(combined) * 10
    }
}
