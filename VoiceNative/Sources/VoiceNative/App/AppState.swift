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
    private var settingsWindow: NSWindow?
    private var sourceApp: NSRunningApplication?

    // Streaming pipeline state
    private var pipelineChunks: [(text: String, endRawIndex: Int)] = []
    private var pipelineTask: Task<Void, Never>?

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

    // MARK: - Settings Window

    func showSettings() {
        // Delay to let MenuBarExtra panel dismiss first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }

            NSApp.activate(ignoringOtherApps: true)

            // Reuse only if still visible; closed windows are unreliable to reshow
            if let window = self.settingsWindow, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return
            }

            // Create fresh window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceNative Settings"
            window.contentView = NSHostingView(rootView: SettingsView().environment(self))
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.level = .normal

            self.settingsWindow = window
        }
    }

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
            pipelineTask?.cancel()
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

        // Remember which app was frontmost so we can paste back into it
        sourceApp = NSWorkspace.shared.frontmostApplication
        // Sync hotkey toggle so next Right Shift is a STOP, not a redundant START
        hotkey.markToggleActive()

        vad.reset()
        vad.resetCalibration()
        vad.autoStopEnabled = triggerMode == .holdToTalk
        pipelineChunks = []

        do {
            try audio.start()
            phase = .listening
            recordingElapsed = 0
            if soundFeedbackEnabled { SoundFeedback.playStartRecording() }
            startRecordingTimer()
            startTranscriptionPipeline()
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

        Task {
            // Wait for any in-flight pipeline chunk to finish (provides more pre-transcribed text)
            pipelineTask?.cancel()
            await pipelineTask?.value

            let chunks = pipelineChunks
            if !chunks.isEmpty {
                print("[AppState] Pipeline completed \(chunks.count) chunks before stop")
            }

            await performFinalTranscription(
                fullBuffer: audioBuffer,
                audioDuration: audioDuration,
                completedChunks: chunks
            )
        }
    }

    func cancelRecording() {
        guard phase == .listening else { return }

        pipelineTask?.cancel()
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

    // MARK: - Streaming Transcription Pipeline

    /// Background pipeline: transcribe 30s chunks while recording continues.
    /// When the user stops, only the remaining audio needs transcription.
    private func startTranscriptionPipeline() {
        pipelineTask?.cancel()
        pipelineTask = Task {
            let chunkSamples = Int(audio.nativeSampleRate * 30)
            var lastProcessedRaw = 0

            while !Task.isCancelled && phase == .listening {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, phase == .listening else { break }

                let currentCount = audio.currentRawSampleCount
                let newSamples = currentCount - lastProcessedRaw
                guard newSamples >= chunkSamples else { continue }

                let rawChunk = audio.snapshotRawSamples(from: lastProcessedRaw)
                let toProcess = Array(rawChunk.prefix(chunkSamples))
                let processed = audio.prepareChunk(toProcess)
                let duration = Double(processed.count) / Constants.Audio.targetSampleRate

                guard duration >= 5.0 else {
                    lastProcessedRaw += chunkSamples
                    continue
                }

                let chunkStart = CFAbsoluteTimeGetCurrent()
                print("[Pipeline] Transcribing chunk \(pipelineChunks.count + 1) at raw[\(lastProcessedRaw)..+\(chunkSamples)] (\(String(format: "%.1f", duration))s)")

                // Always advance past this chunk to prevent re-transcribing the same audio
                lastProcessedRaw += chunkSamples

                do {
                    let text = try await transcription.transcribeChunk(
                        audioBuffer: processed,
                        audioDuration: duration
                    )
                    let elapsed = CFAbsoluteTimeGetCurrent() - chunkStart
                    if !text.isEmpty {
                        pipelineChunks.append((text: text, endRawIndex: lastProcessedRaw))
                        print("[Pipeline] Chunk \(pipelineChunks.count) done in \(String(format: "%.1f", elapsed))s: \"\(text.prefix(80))...\"")
                    } else {
                        print("[Pipeline] Chunk returned empty in \(String(format: "%.1f", elapsed))s, skipping")
                    }
                } catch {
                    print("[Pipeline] Chunk error: \(error)")
                }
            }
            print("[Pipeline] Exited (\(pipelineChunks.count) chunks completed)")
        }
    }

    // MARK: - Final Transcription

    private func performFinalTranscription(
        fullBuffer: [Float],
        audioDuration: TimeInterval,
        completedChunks: [(text: String, endRawIndex: Int)]
    ) async {
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

        do {
            let text: String

            if completedChunks.isEmpty {
                // No pipeline results -- transcribe everything
                print("[AppState] No pipeline chunks, transcribing full \(String(format: "%.1f", audioDuration))s")
                text = try await transcription.transcribe(
                    audioBuffer: fullBuffer,
                    audioDuration: audioDuration,
                    dictionary: TechnicalDictionary.allTerms(customStorage: customDictionaryTerms)
                )
            } else {
                // Pipeline completed chunks -- only transcribe the remaining tail
                let lastRawEnd = completedChunks.last!.endRawIndex
                let ratio = Constants.Audio.targetSampleRate / audio.nativeSampleRate
                let processedOffset = min(Int(Double(lastRawEnd) * ratio), fullBuffer.count)

                let pipelineTexts = completedChunks.map(\.text)
                let remainingBuffer = Array(fullBuffer[processedOffset...])
                let remainingDuration = Double(remainingBuffer.count) / Constants.Audio.targetSampleRate

                print("[AppState] Pipeline had \(completedChunks.count) chunks, remaining: \(String(format: "%.1f", remainingDuration))s")

                var remainingText = ""
                if remainingDuration >= 1.0 && !remainingBuffer.isEmpty {
                    remainingText = try await transcription.transcribe(
                        audioBuffer: remainingBuffer,
                        audioDuration: remainingDuration,
                        dictionary: TechnicalDictionary.allTerms(customStorage: customDictionaryTerms)
                    )
                }

                let allParts = pipelineTexts + (remainingText.isEmpty ? [] : [remainingText])
                text = allParts.joined(separator: " ")
            }

            audio.reset()

            guard !text.isEmpty else {
                showNoSpeechFeedback()
                return
            }

            let pipelineTime = CFAbsoluteTimeGetCurrent() - pipelineStart
            print("[AppState] Final pipeline: \(String(format: "%.2f", pipelineTime))s for \(String(format: "%.1f", audioDuration))s audio (after-stop only)")

            lastTranscription = text
            injection.inject(text, autoPaste: autoPaste, targetApp: sourceApp)
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
