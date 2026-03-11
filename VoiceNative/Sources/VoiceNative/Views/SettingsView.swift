import SwiftUI
@preconcurrency import AVFoundation

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }

            TranscriptionSettingsTab()
                .environment(appState)
                .tabItem { Label("Transcription", systemImage: "waveform") }

            OutputSettingsTab()
                .tabItem { Label("Output", systemImage: "doc.on.clipboard") }

            DictionarySettingsTab()
                .tabItem { Label("Dictionary", systemImage: "text.book.closed") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("triggerMode") private var triggerMode = TriggerMode.toggle
    @AppStorage("soundFeedback") private var soundFeedback = true
    @AppStorage("maxRecordingDuration") private var maxRecordingDuration = Constants.Recording.defaultMaxDuration

    @State private var launchManager = LaunchAtLoginManager()

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Trigger Mode", selection: $triggerMode) {
                    Text("Toggle (press to start/stop)").tag(TriggerMode.toggle)
                    Text("Hold to Talk").tag(TriggerMode.holdToTalk)
                }
                .onChange(of: triggerMode) { appState.applySettingsLive() }

                HStack {
                    Text("Trigger Key")
                    Spacer()
                    Text("Right Shift")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recording") {
                HStack {
                    Text("Max Duration")
                    Spacer()
                    Text(formatDuration(maxRecordingDuration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $maxRecordingDuration, in: 30...600, step: 30)

                MicrophonePicker()
            }

            Section {
                Toggle("Launch at Login", isOn: $launchManager.isEnabled)
                Toggle("Sound Feedback", isOn: $soundFeedback)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
    }
}

// MARK: - Transcription

struct TranscriptionSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("selectedModel") private var selectedModel = WhisperModel.largev3TurboQuantized
    @AppStorage("silenceTimeout") private var silenceTimeout = 3.0
    @AppStorage("vadSensitivity") private var vadSensitivity = VADSensitivity.medium

    @State private var showModelChangeAlert = false

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        HStack {
                            Text(model.displayName)
                            if model.isRecommended {
                                Text("Recommended")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .tag(model)
                    }
                }
                .onChange(of: selectedModel) { showModelChangeAlert = true }
                .alert("Reload Model?", isPresented: $showModelChangeAlert) {
                    Button("Reload Now") { appState.reloadModel() }
                    Button("Later", role: .cancel) {}
                } message: {
                    Text("The new model will be downloaded if needed. This may take a moment.")
                }
            }

            Section("Voice Detection") {
                HStack {
                    Text("Silence Timeout")
                    Spacer()
                    Text(String(format: "%.1fs", silenceTimeout))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $silenceTimeout, in: 1.0...5.0, step: 0.5)
                    .onChange(of: silenceTimeout) { appState.applySettingsLive() }

                Picker("VAD Sensitivity", selection: $vadSensitivity) {
                    Text("Low").tag(VADSensitivity.low)
                    Text("Medium").tag(VADSensitivity.medium)
                    Text("High").tag(VADSensitivity.high)
                }
                .onChange(of: vadSensitivity) { appState.applySettingsLive() }

                Text("In Toggle mode, VAD is disabled. Only active in Hold-to-Talk mode.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Output

struct OutputSettingsTab: View {
    @AppStorage("autoPaste") private var autoPaste = true

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Paste (Cmd+V after copy)", isOn: $autoPaste)
                Text("When enabled, transcribed text is automatically pasted into the focused app. Previous clipboard contents are restored after paste.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Dictionary

struct DictionarySettingsTab: View {
    @AppStorage("customDictionaryTerms") private var customTermsStorage = ""

    var body: some View {
        Form {
            Section("Default Terms") {
                ScrollView {
                    Text(TechnicalDictionary.defaultTerms.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
            }

            Section("Custom Terms (one per line)") {
                TextEditor(text: $customTermsStorage)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)

                Text("Dictionary terms are injected as prompt tokens to bias transcription toward technical vocabulary. For short recordings (< 3s), only a minimal prompt is used.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Microphone Picker

struct MicrophonePicker: View {
    @State private var devices: [AVCaptureDevice] = []
    @State private var selectedDeviceID: String = ""

    var body: some View {
        Picker("Microphone", selection: $selectedDeviceID) {
            Text("System Default").tag("")
            ForEach(devices, id: \.uniqueID) { device in
                Text(device.localizedName).tag(device.uniqueID)
            }
        }
        .onAppear { refreshDevices() }
        .onChange(of: selectedDeviceID) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "preferredMicrophoneID")
        }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = discovery.devices
        selectedDeviceID = UserDefaults.standard.string(forKey: "preferredMicrophoneID") ?? ""
    }
}
