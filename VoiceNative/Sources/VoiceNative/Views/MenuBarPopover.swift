import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            if appState.phase == .listening {
                Text(formattedElapsed)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            actionButton

            if !appState.lastTranscription.isEmpty {
                iconButton("doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                }
                .help("Copy")
            }

            iconButton("clock.arrow.circlepath") { appState.showHistory() }
                .help("History")

            iconButton("gear") { appState.showSettings() }
                .help("Settings")

            iconButton("power", style: .tertiary) {
                appState.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
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

    private var formattedElapsed: String {
        let elapsed = Int(appState.recordingElapsed)
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch appState.phase {
        case .ready:
            iconButton("mic.fill", tint: .blue) { appState.toggleRecording() }
        case .listening:
            iconButton("stop.fill", tint: .red) { appState.toggleRecording() }
        case .processing, .modelLoading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .error:
            iconButton("arrow.clockwise", tint: .orange) { appState.retryModelLoad() }
        case .idle:
            EmptyView()
        }
    }

    private func iconButton(
        _ symbol: String,
        tint: Color? = nil,
        style: HierarchicalShapeStyle = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(tint ?? Color(.secondaryLabelColor))
        }
        .buttonStyle(.plain)
    }
}
