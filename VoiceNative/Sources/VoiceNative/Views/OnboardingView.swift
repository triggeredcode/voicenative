import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 24) {
            header

            Divider()

            if currentStep == 0 {
                permissionsStep
            } else {
                modelDownloadStep
            }

            Spacer()

            footer
        }
        .padding(24)
        .frame(width: 420, height: 500)
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

            Text(currentStep == 0
                 ? "Grant permissions to enable voice transcription"
                 : "Download the speech recognition model")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            PermissionRow(
                title: "Microphone",
                description: "Required to capture your voice",
                status: appState.permissions.microphoneStatus,
                action: {
                    Task { await appState.permissions.requestMicrophonePermission() }
                },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .microphone)
                }
            )

            PermissionRow(
                title: "Accessibility",
                description: "Required to paste text into apps",
                status: appState.permissions.accessibilityStatus,
                action: { appState.permissions.requestAccessibilityPermission() },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .accessibility)
                }
            )

            PermissionRow(
                title: "Input Monitoring",
                description: "Required for global hotkey",
                status: appState.permissions.inputMonitoringStatus,
                action: { appState.permissions.requestInputMonitoringPermission() },
                openSettings: {
                    appState.permissions.openSystemPreferences(for: .inputMonitoring)
                }
            )
        }
    }

    // MARK: - Step 2: Model Download

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                Text("One-Time Model Download")
                    .font(.headline)

                Text("VoiceNative needs to download a speech recognition model (~950 MB). After this, the app works completely offline with zero external dependencies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            if appState.phase == .modelLoading {
                VStack(spacing: 6) {
                    ProgressView(value: appState.modelLoadProgress)
                        .progressViewStyle(.linear)

                    Text(appState.transcription.loadStatus)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
            }

            if appState.phase == .ready {
                Label("Model loaded successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if appState.phase == .error {
                VStack(spacing: 8) {
                    Label("Download failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)

                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Retry Download") {
                        appState.retryModelLoad()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text("100% local processing. No data leaves your Mac.")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if currentStep == 0 {
                if appState.permissions.allPermissionsGranted {
                    Label("All permissions granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                HStack {
                    Button("Refresh Status") {
                        appState.permissions.checkAllPermissions()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        currentStep = 1
                    } label: {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.permissions.allPermissionsGranted)
                }
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.phase != .ready)
            }
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
            Button("Open Settings") { openSettings() }
                .buttonStyle(.bordered)
                .controlSize(.small)

        case .notDetermined:
            Button("Grant") { action() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
