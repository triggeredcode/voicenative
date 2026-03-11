import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 8) {
            topBar
            actionArea
            Divider()
            bottomBar
        }
        .padding(10)
        .frame(width: 200)
    }

    // MARK: - Top: status dot + optional timer + settings/quit

    private var topBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if appState.phase == .listening {
                Text(formattedElapsed)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { appState.showSettings() } label: {
                Image(systemName: "gear")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                appState.shutdown()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var formattedElapsed: String {
        let elapsed = Int(appState.recordingElapsed)
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
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

    // MARK: - Center: primary action

    @ViewBuilder
    private var actionArea: some View {
        switch appState.phase {
        case .ready:
            Button { appState.toggleRecording() } label: {
                Image(systemName: "mic.fill")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

        case .listening:
            HStack(spacing: 6) {
                Button { appState.toggleRecording() } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(.red.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button { appState.cancelRecording() } label: {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.quaternary.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

        case .processing, .modelLoading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 32)

        case .error:
            Button { appState.retryModelLoad() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(.orange.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

        case .idle:
            EmptyView()
        }
    }

    // MARK: - Bottom: copy + history (same visual weight as top bar)

    private var bottomBar: some View {
        HStack {
            if !appState.lastTranscription.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy last transcription")
            }

            Spacer()

            Button {
                appState.showHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("History")
        }
    }
}
