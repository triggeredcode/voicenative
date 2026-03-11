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

    // Transient icon states shown briefly then auto-reverted
    enum IconFeedback: Equatable, Sendable {
        case none
        case copied
        case noSpeech
        case cancelled
    }

    var phase: Phase = .idle
    var lastTranscription: String = ""
    var errorMessage: String?
    var modelLoadProgress: Double = 0
    var iconFeedback: IconFeedback = .none
    var recordingElapsed: TimeInterval = 0

    /// True after first bootstrap -- checked by VoiceNativeApp to avoid re-running setup on popover re-open
    private(set) var hasBootstrapped = false

    let audio = AudioCaptureService()
    let transcription = TranscriptionService()
    let hotkey = HotkeyService()
    let injection = TextInjectionService()
    let vad = VADService()
    let permissions = PermissionManager()

    @ObservationIgnored
    @AppStorage("selectedModel") private var selectedModel = WhisperModel.largev3TurboQuantized
    @ObservationIgnored
    @AppStorage("autoPaste") private var autoPaste = true
    @ObservationIgnored
    @AppStorage("triggerMode") private var triggerMode = TriggerMode.toggle
    @ObservationIgnored
    @AppStorage("silenceTimeout") private var silenceTimeout = 3.0
    @ObservationIgnored
    @AppStorage("vadSensitivity") private var vadSensitivity = VADSensitivity.medium
    @ObservationIgnored
    @AppStorage("customDictionaryTerms") private var customDictionaryTerms = ""
    @ObservationIgnored
    @AppStorage("soundFeedback") private var soundFeedbackEnabled = true
    @ObservationIgnored
    @AppStorage("maxRecordingDuration") private var maxRecordingDuration = Constants.Recording.defaultMaxDuration

    private var modelContext: ModelContext?
    private var recordingTimer: Task<Void, Never>?
    private var feedbackTimer: Task<Void, Never>?
    private var keepaliveTimer: Task<Void, Never>?
    private var audioDeviceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Computed Properties

    var menuBarIcon: String {
        switch iconFeedback {
        case .copied: return "checkmark.circle.fill"
        case .noSpeech: return "mic.slash"
        case .cancelled: return "xmark.circle"
        case .none: break
        }

        switch phase {
        case .idle, .modelLoading: return "arrow.down.circle"
        case .ready: return "mic"
        case .listening: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var isIconAnimating: Bool {
        iconFeedback == .none && (phase == .listening || phase == .processing || phase == .modelLoading)
    }

    var statusText: String {
        switch phase {
        case .error: return errorMessage ?? "Unknown error"
        case .listening:
            let elapsed = Int(recordingElapsed)
            let mins = elapsed / 60
            let secs = elapsed % 60
            return "Listening \(String(format: "%d:%02d", mins, secs))"
        default: return phase.rawValue
        }
    }

    var isRecordingAvailable: Bool { phase == .ready }

    // MARK: - Lifecycle

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func initialize() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        print("[AppState] Initializing...")
        permissions.checkAllPermissions()
        configureServices()
        registerAudioDeviceObserver()
        registerWakeObserver()
        await loadModel()
        await transcription.prewarm()
        startKeepaliveTimer()
        print("[AppState] Initialization complete (phase=\(phase.rawValue))")
    }

    func shutdown() {
        if phase == .listening {
            let _ = audio.stop()
            audio.reset()
        }
        recordingTimer?.cancel()
        feedbackTimer?.cancel()
        keepaliveTimer?.cancel()
        hotkey.stopListening()
        if let obs = audioDeviceObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Service Configuration

    private func configureServices() {
        hotkey.triggerMode = triggerMode

        hotkey.onTriggerStart = { [weak self] in
            Task { @MainActor in self?.handleTriggerStart() }
        }
        hotkey.onTriggerEnd = { [weak self] in
            Task { @MainActor in self?.handleTriggerEnd() }
        }
        hotkey.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }

        vad.silenceTimeout = silenceTimeout
        vad.sensitivity = vadSensitivity
        vad.onSilenceDetected = { [weak self] in
            Task { @MainActor in self?.handleSilenceDetected() }
        }

        audio.onAudioChunk = { [weak self] samples in
            Task { @MainActor in self?.vad.processAudioChunk(samples) }
        }
    }

    func applySettingsLive() {
        hotkey.triggerMode = triggerMode
        vad.silenceTimeout = silenceTimeout
        vad.sensitivity = vadSensitivity
    }

    // MARK: - Model Loading

    private func loadModel() async {
        // Never interrupt recording or processing to load a model
        guard phase == .idle || phase == .error || phase == .modelLoading else {
            print("[AppState] loadModel skipped (phase=\(phase.rawValue))")
            return
        }
        phase = .modelLoading
        modelLoadProgress = 0

        do {
            try await transcription.loadModel(selectedModel)
            // Only transition to .ready if we're still in .modelLoading (not interrupted)
            if phase == .modelLoading {
                phase = .ready
                hotkey.startListening()
            }
        } catch {
            if phase == .modelLoading {
                setError("Failed to load model: \(error.localizedDescription)")
            }
        }
    }

    func reloadModel() {
        guard phase == .ready || phase == .error else {
            print("[AppState] reloadModel skipped (phase=\(phase.rawValue))")
            return
        }
        Task {
            hotkey.stopListening()
            transcription.unloadModel()
            await loadModel()
        }
    }

    private func startKeepaliveTimer() {
        keepaliveTimer?.cancel()
        keepaliveTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { continue }
                guard phase == .ready else { continue }
                await transcription.prewarm()
            }
        }
    }

    // MARK: - Trigger Handling

    private func handleTriggerStart() {
        guard phase == .ready else { return }
        startRecording()
    }

    private func handleTriggerEnd() {
        guard phase == .listening else { return }
        stopRecordingAndTranscribe()
    }

    private func handleSilenceDetected() {
        guard phase == .listening else { return }
        // In toggle mode, VAD doesn't auto-stop
        guard triggerMode == .holdToTalk else { return }
        stopRecordingAndTranscribe()
    }

    // MARK: - Recording

    func startRecording() {
        guard phase == .ready else { return }

        vad.reset()
        vad.resetCalibration()

        // In toggle mode, disable VAD auto-stop
        vad.autoStopEnabled = triggerMode == .holdToTalk

        do {
            try audio.start()
            phase = .listening
            recordingElapsed = 0
            if soundFeedbackEnabled { SoundFeedback.playStartRecording() }
            startRecordingTimer()
        } catch {
            setError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndTranscribe() {
        guard phase == .listening else { return }

        recordingTimer?.cancel()
        let audioBuffer = audio.stop()
        let audioDuration = audio.audioDuration

        phase = .processing
        if soundFeedbackEnabled { SoundFeedback.playStopRecording() }

        Task { await performTranscription(audioBuffer: audioBuffer, audioDuration: audioDuration) }
    }

    func cancelRecording() {
        guard phase == .listening else { return }

        recordingTimer?.cancel()
        let _ = audio.stop()
        audio.reset()
        hotkey.resetToggleState()

        phase = .ready
        if soundFeedbackEnabled { SoundFeedback.playCancelled() }
        showIconFeedback(.cancelled)
        print("[AppState] Recording cancelled")
    }

    func toggleRecording() {
        switch phase {
        case .ready: startRecording()
        case .listening: stopRecordingAndTranscribe()
        default: break
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = Task {
            while !Task.isCancelled && phase == .listening {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, phase == .listening else { break }
                recordingElapsed = audio.currentRecordingDuration

                if recordingElapsed >= maxRecordingDuration {
                    print("[AppState] Max recording duration reached (\(Int(maxRecordingDuration))s)")
                    stopRecordingAndTranscribe()
                    break
                }
            }
        }
    }

    // MARK: - Transcription

    private func performTranscription(audioBuffer: [Float], audioDuration: TimeInterval) async {
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        let minDuration = Constants.Recording.minimumDurationForTranscription
        guard audioDuration >= minDuration else {
            print("[AppState] Audio too short (\(String(format: "%.1f", audioDuration))s < \(minDuration)s)")
            showNoSpeechFeedback()
            audio.reset()
            return
        }

        do {
            try await transcription.ensureModelReady(selectedModel)
        } catch {
            setError("Model unavailable: \(error.localizedDescription)")
            audio.reset()
            return
        }

        let dictionary = TechnicalDictionary.allTerms(customStorage: customDictionaryTerms)

        do {
            let text = try await transcription.transcribe(
                audioBuffer: audioBuffer,
                audioDuration: audioDuration,
                dictionary: dictionary
            )

            audio.reset()

            guard !text.isEmpty else {
                showNoSpeechFeedback()
                return
            }

            let pipelineTime = CFAbsoluteTimeGetCurrent() - pipelineStart
            print("[AppState] Full pipeline: \(String(format: "%.2f", pipelineTime))s for \(String(format: "%.1f", audioDuration))s audio")

            lastTranscription = text
            injection.inject(text, autoPaste: autoPaste)
            saveTranscription(text: text, audioDuration: audioDuration)

            phase = .ready
            showIconFeedback(.copied)
            if soundFeedbackEnabled { SoundFeedback.playCopied() }
        } catch {
            audio.reset()
            print("[AppState] Transcription failed: \(error)")
            setError("Transcription failed: \(error.localizedDescription)")
            if soundFeedbackEnabled { SoundFeedback.playError() }
        }
    }

    private func showNoSpeechFeedback() {
        phase = .ready
        showIconFeedback(.noSpeech)
        if soundFeedbackEnabled { SoundFeedback.playNoSpeech() }
        print("[AppState] No speech detected")
    }

    // MARK: - Icon Feedback

    private func showIconFeedback(_ feedback: IconFeedback) {
        feedbackTimer?.cancel()
        iconFeedback = feedback
        feedbackTimer = Task {
            try? await Task.sleep(for: .seconds(Constants.MenuBarIcon.feedbackDuration))
            guard !Task.isCancelled else { return }
            iconFeedback = .none
        }
    }

    // MARK: - Persistence

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

    // MARK: - Error

    func setError(_ message: String) {
        // Never clobber active recording/processing with an error
        guard phase != .listening else {
            print("[AppState] Suppressed error during recording: \(message)")
            return
        }
        errorMessage = message
        phase = .error
    }

    func retryModelLoad() {
        guard phase == .error else { return }
        Task { await loadModel() }
    }

    // MARK: - Wake from Sleep

    private func registerWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Delay 3s after wake to let system settle, then only prewarm if idle
                try? await Task.sleep(for: .seconds(3))
                guard self.phase == .ready, !self.transcription.isTranscribing else { return }
                print("[AppState] Woke from sleep, prewarming model...")
                await self.transcription.prewarm()
            }
        }
    }

    // MARK: - Audio Device Change

    private func registerAudioDeviceObserver() {
        audioDeviceObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audio,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .listening else { return }
                print("[AppState] Audio device changed during recording, stopping...")
                self.cancelRecording()
            }
        }
    }
}
