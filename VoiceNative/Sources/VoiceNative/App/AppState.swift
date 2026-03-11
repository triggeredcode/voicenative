import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase: String, Equatable, Sendable {
        case idle = "Initializing"
        case modelLoading = "Loading Model"
        case ready = "Ready"
        case listening = "Listening"
        case processing = "Processing"
        case error = "Error"
    }
    
    var phase: Phase = .idle
    var lastTranscription: String = ""
    var errorMessage: String?
    var modelLoadProgress: Double = 0
    
    let audio = AudioCaptureService()
    let transcription = TranscriptionService()
    let hotkey = HotkeyService()
    let injection = TextInjectionService()
    let vad = VADService()
    let hud = HUDOverlayController()
    let permissions = PermissionManager()
    
    @ObservationIgnored
    @AppStorage("selectedModel") private var selectedModel = WhisperModel.largev3Turbo
    
    @ObservationIgnored
    @AppStorage("autoPaste") private var autoPaste = true
    
    @ObservationIgnored
    @AppStorage("triggerMode") private var triggerMode = TriggerMode.toggle
    
    @ObservationIgnored
    @AppStorage("silenceTimeout") private var silenceTimeout = 1.5
    
    @ObservationIgnored
    @AppStorage("vadSensitivity") private var vadSensitivity = VADSensitivity.medium
    
    @ObservationIgnored
    @AppStorage("hudPosition") private var hudPosition = HUDPosition.topCenter
    
    @ObservationIgnored
    @AppStorage("hudOpacity") private var hudOpacity = 0.85
    
    @ObservationIgnored
    @AppStorage("customDictionaryTerms") private var customDictionaryTerms = ""
    
    @ObservationIgnored
    @AppStorage("soundFeedback") private var soundFeedbackEnabled = true
    
    private var modelContext: ModelContext?
    
    var menuBarIcon: String {
        switch phase {
        case .idle, .modelLoading:
            return "mic.slash"
        case .ready:
            return "mic"
        case .listening:
            return "mic.fill"
        case .processing:
            return "ellipsis.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
    
    var statusText: String {
        switch phase {
        case .error:
            return errorMessage ?? "Unknown error"
        default:
            return phase.rawValue
        }
    }
    
    var isRecordingAvailable: Bool {
        phase == .ready
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func initialize() async {
        permissions.checkAllPermissions()
        
        configureServices()
        
        await loadModel()
    }
    
    private func configureServices() {
        hotkey.triggerMode = triggerMode
        hotkey.onTriggerStart = { [weak self] in
            Task { @MainActor in
                self?.handleTriggerStart()
            }
        }
        hotkey.onTriggerEnd = { [weak self] in
            Task { @MainActor in
                self?.handleTriggerEnd()
            }
        }
        
        vad.silenceTimeout = silenceTimeout
        vad.sensitivity = vadSensitivity
        vad.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                self?.handleSilenceDetected()
            }
        }
        
        audio.onAudioChunk = { [weak self] samples in
            Task { @MainActor in
                self?.vad.processAudioChunk(samples)
            }
        }
        
        hud.position = hudPosition
        hud.opacity = hudOpacity
    }
    
    private func loadModel() async {
        phase = .modelLoading
        
        do {
            try await transcription.loadModel(selectedModel)
            phase = .ready
            hotkey.startListening()
        } catch {
            setError("Failed to load model: \(error.localizedDescription)")
        }
    }
    
    private func handleTriggerStart() {
        guard phase == .ready else { return }
        startRecording()
    }
    
    private func handleTriggerEnd() {
        guard phase == .listening else { return }
        if triggerMode == .holdToTalk {
            stopRecordingAndTranscribe()
        }
    }
    
    private func handleSilenceDetected() {
        guard phase == .listening else { return }
        if triggerMode == .toggle {
            hotkey.simulateToggleEnd()
        }
        stopRecordingAndTranscribe()
    }
    
    func startRecording() {
        guard phase == .ready else { return }
        
        vad.resetCalibration()
        
        do {
            try audio.start()
            phase = .listening
            hud.show(state: .listening)
            if soundFeedbackEnabled {
                SoundFeedback.playStartRecording()
            }
        } catch {
            setError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecordingAndTranscribe() {
        guard phase == .listening else { return }
        
        let audioBuffer = audio.stop()
        let audioDuration = audio.audioDuration
        
        phase = .processing
        hud.show(state: .processing)
        
        if soundFeedbackEnabled {
            SoundFeedback.playStopRecording()
        }
        
        Task {
            await performTranscription(audioBuffer: audioBuffer, audioDuration: audioDuration)
        }
    }
    
    private func performTranscription(audioBuffer: [Float], audioDuration: TimeInterval) async {
        let dictionary = TechnicalDictionary.allTerms(customStorage: customDictionaryTerms)
        
        do {
            let text = try await transcription.transcribe(audioBuffer: audioBuffer, dictionary: dictionary)
            
            guard !text.isEmpty else {
                phase = .ready
                hud.hide()
                return
            }
            
            lastTranscription = text
            
            injection.inject(text, autoPaste: autoPaste)
            
            saveTranscription(text: text, audioDuration: audioDuration)
            
            phase = .ready
            hud.show(state: .copied)
            
            if soundFeedbackEnabled {
                SoundFeedback.playCopied()
            }
        } catch {
            setError("Transcription failed: \(error.localizedDescription)")
            hud.hide()
            if soundFeedbackEnabled {
                SoundFeedback.playError()
            }
        }
    }
    
    private func saveTranscription(text: String, audioDuration: TimeInterval) {
        guard let modelContext else { return }
        
        let record = TranscriptionRecord(
            text: text,
            modelVersion: transcription.currentModel,
            audioDuration: audioDuration
        )
        modelContext.insert(record)
        
        try? modelContext.save()
    }
    
    func setError(_ message: String) {
        errorMessage = message
        phase = .error
    }
    
    func retryModelLoad() {
        Task {
            await loadModel()
        }
    }
    
    func toggleRecording() {
        switch phase {
        case .ready:
            startRecording()
        case .listening:
            stopRecordingAndTranscribe()
        default:
            break
        }
    }
}
