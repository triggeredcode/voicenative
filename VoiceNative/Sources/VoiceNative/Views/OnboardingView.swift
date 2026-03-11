import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            header
            
            Divider()
            
            permissionsList
            
            Spacer()
            
            footer
        }
        .padding(24)
        .frame(width: 400, height: 450)
        .onAppear {
            appState.permissions.checkAllPermissions()
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            
            Text("Welcome to VoiceNative")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Grant permissions to enable voice transcription")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var permissionsList: some View {
        VStack(spacing: 16) {
            PermissionRow(
                title: "Microphone",
                description: "Required to capture your voice",
                status: appState.permissions.microphoneStatus,
                action: {
                    Task {
                        await appState.permissions.requestMicrophonePermission()
                    }
                },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .microphone)
                }
            )
            
            PermissionRow(
                title: "Accessibility",
                description: "Required to paste text into apps",
                status: appState.permissions.accessibilityStatus,
                action: {
                    appState.permissions.requestAccessibilityPermission()
                },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .accessibility)
                }
            )
            
            PermissionRow(
                title: "Input Monitoring",
                description: "Required for global hotkey",
                status: appState.permissions.inputMonitoringStatus,
                action: {
                    appState.permissions.requestInputMonitoringPermission()
                },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .inputMonitoring)
                }
            )
        }
    }
    
    private var footer: some View {
        VStack(spacing: 12) {
            if appState.permissions.allPermissionsGranted {
                Label("All permissions granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            
            Button {
                appState.permissions.checkAllPermissions()
            } label: {
                Text("Refresh Status")
            }
            .buttonStyle(.bordered)
            
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.permissions.allPermissionsGranted)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let status: PermissionManager.PermissionStatus
    let action: () -> Void
    let openSettings: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            statusView
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            
        case .denied:
            Button("Open Settings") {
                openSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
        case .notDetermined:
            Button("Grant") {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
