import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            TranscriptionSettingsTab()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
            
            OutputSettingsTab()
                .tabItem {
                    Label("Output", systemImage: "doc.on.clipboard")
                }
            
            DictionarySettingsTab()
                .tabItem {
                    Label("Dictionary", systemImage: "text.book.closed")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("triggerMode") private var triggerMode = TriggerMode.toggle
    @AppStorage("soundFeedback") private var soundFeedback = true
    
    @State private var launchManager = LaunchAtLoginManager()
    
    var body: some View {
        Form {
            Section {
                Picker("Trigger Mode", selection: $triggerMode) {
                    Text("Toggle (press to start/stop)").tag(TriggerMode.toggle)
                    Text("Hold to Talk").tag(TriggerMode.holdToTalk)
                }
                
                HStack {
                    Text("Trigger Key")
                    Spacer()
                    Text("Right Shift")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Toggle("Launch at Login", isOn: $launchManager.isEnabled)
                Toggle("Sound Feedback", isOn: $soundFeedback)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TranscriptionSettingsTab: View {
    @AppStorage("selectedModel") private var selectedModel = WhisperModel.largev3Turbo
    @AppStorage("silenceTimeout") private var silenceTimeout = 1.5
    @AppStorage("vadSensitivity") private var vadSensitivity = VADSensitivity.medium
    
    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $selectedModel) {
                    Text("Large v3 Turbo (Recommended)").tag(WhisperModel.largev3Turbo)
                    Text("Distil Large v3").tag(WhisperModel.distilLargev3)
                }
            }
            
            Section {
                HStack {
                    Text("Silence Timeout")
                    Spacer()
                    Text(String(format: "%.1fs", silenceTimeout))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $silenceTimeout, in: 0.5...5.0, step: 0.5)
                
                Picker("VAD Sensitivity", selection: $vadSensitivity) {
                    Text("Low").tag(VADSensitivity.low)
                    Text("Medium").tag(VADSensitivity.medium)
                    Text("High").tag(VADSensitivity.high)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct OutputSettingsTab: View {
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("hudPosition") private var hudPosition = HUDPosition.topCenter
    @AppStorage("hudOpacity") private var hudOpacity = 0.85
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-Paste (Cmd+V after copy)", isOn: $autoPaste)
            }
            
            Section("HUD Overlay") {
                Picker("Position", selection: $hudPosition) {
                    Text("Top Center").tag(HUDPosition.topCenter)
                    Text("Near Cursor").tag(HUDPosition.nearCursor)
                    Text("Off").tag(HUDPosition.off)
                }
                
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text(String(format: "%.0f%%", hudOpacity * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $hudOpacity, in: 0.3...1.0)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

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
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
