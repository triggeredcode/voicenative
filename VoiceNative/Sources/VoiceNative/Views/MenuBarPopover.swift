import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            
            Divider()
            
            statusSection
            
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
            SettingsLink {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
            }
            
            if appState.phase == .modelLoading {
                ProgressView(value: appState.modelLoadProgress)
                    .progressViewStyle(.linear)
            }
            
            Text("Right Shift to record")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var statusColor: Color {
        switch appState.phase {
        case .idle, .modelLoading:
            return .gray
        case .ready:
            return .green
        case .listening:
            return .red
        case .processing:
            return .orange
        case .error:
            return .red
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
                    copyToClipboard(appState.lastTranscription)
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
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    MenuBarPopover()
        .environment(AppState())
}
