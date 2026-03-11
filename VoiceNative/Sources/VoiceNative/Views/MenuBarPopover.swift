import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            statusSection
            recordButton
            if !appState.lastTranscription.isEmpty {
                Divider()
                lastTranscriptionSection
            }
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 300)
    }

    private var headerSection: some View {
        HStack {
            Text("VoiceNative")
                .font(.headline)
            Spacer()
            Button {
                print("[MenuBar] Settings button pressed")
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear")
                    .font(.body)
            }
            .buttonStyle(.borderless)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if appState.phase == .modelLoading {
                ProgressView(value: appState.modelLoadProgress)
                    .progressViewStyle(.linear)
                Text(appState.transcription.loadStatus)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if appState.phase == .error {
                Button("Retry") {
                    appState.retryModelLoad()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if appState.phase == .ready {
                Text("Right Shift to record \u{2022} Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusColor: Color {
        switch appState.phase {
        case .idle, .modelLoading: return .gray
        case .ready: return .green
        case .listening: return .red
        case .processing: return .orange
        case .error: return .red
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        if appState.phase == .ready || appState.phase == .listening {
            HStack(spacing: 8) {
                Button {
                    appState.toggleRecording()
                } label: {
                    HStack {
                        Image(systemName: appState.phase == .listening ? "stop.fill" : "mic.fill")
                        Text(appState.phase == .listening ? "Stop Recording" : "Start Recording")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.phase == .listening ? .red : .accentColor)
                .controlSize(.large)

                if appState.phase == .listening {
                    Button {
                        appState.cancelRecording()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Cancel recording (Esc)")
                }
            }
        }
    }

    private var lastTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Transcription")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(alignment: .top) {
                Text(appState.lastTranscription)
                    .font(.callout)
                    .lineLimit(3)
                    .truncationMode(.tail)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("History") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Quit") {
                appState.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
