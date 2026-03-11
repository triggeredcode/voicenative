import Foundation
import WhisperKit
import Observation

@Observable
final class TranscriptionService: @unchecked Sendable {
    private var whisperKit: WhisperKit?

    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var loadProgress: Double = 0
    private(set) var loadStatus: String = ""
    private(set) var currentModel: String = ""

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModel) async throws {
        let cached = isModelCached(model)

        await MainActor.run {
            isModelLoaded = false
            loadProgress = 0
            loadStatus = cached ? "Loading model from cache..." : "Downloading model (~\(model.sizeEstimate))..."
            currentModel = model.rawValue
        }

        print("[Transcription] Loading model: \(model.rawValue) (cached: \(cached))")

        let config = WhisperKitConfig(
            model: model.rawValue,
            verbose: true,
            logLevel: .info,
            prewarm: false,
            load: true,
            download: true
        )

        whisperKit = try await WhisperKit(config)

        await MainActor.run {
            isModelLoaded = true
            loadProgress = 1.0
            loadStatus = "Ready"
        }

        print("[Transcription] Model loaded successfully: \(model.rawValue)")
    }

    /// Ensure model is ready before transcription. Reloads if CoreML evicted it.
    func ensureModelReady(_ model: WhisperModel) async throws {
        guard let wk = whisperKit else {
            try await loadModel(model)
            return
        }

        let state = wk.modelState
        if state != .loaded {
            print("[Transcription] Model state is \(state), reloading...")
            await MainActor.run { loadStatus = "Reloading model..." }
            try await wk.loadModels()
            await MainActor.run { loadStatus = "Ready" }
            print("[Transcription] Model reloaded")
        }
    }

    /// Run a micro-inference on 0.5s of silence to keep CoreML/ANE warm.
    /// Prevents model eviction after idle periods or wake from sleep.
    func prewarm() async {
        guard let whisperKit, isModelLoaded, !isTranscribing else { return }
        let silence = [Float](repeating: 0, count: 8000) // 0.5s at 16kHz
        let options = DecodingOptions(task: .transcribe, language: "en", withoutTimestamps: true)
        print("[Transcription] Prewarm: running micro-inference...")
        _ = try? await whisperKit.transcribe(audioArray: silence, decodeOptions: options)
        print("[Transcription] Prewarm complete")
    }

    // MARK: - Transcription

    func transcribe(
        audioBuffer: [Float],
        audioDuration: TimeInterval,
        dictionary: [String] = []
    ) async throws -> String {
        guard let whisperKit, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        let sampleCount = audioBuffer.count
        print("[Transcription] Starting: \(sampleCount) samples (~\(String(format: "%.1f", audioDuration))s)")

        guard sampleCount > 0 else {
            throw TranscriptionError.emptyAudioBuffer
        }

        await MainActor.run { isTranscribing = true }
        defer { Task { @MainActor in self.isTranscribing = false } }

        var options = DecodingOptions(task: .transcribe, language: "en")

        // Instructional initial prompt for technical content
        options.clipTimestamps = [0]

        // Scale dictionary injection by audio duration
        if audioDuration > 3.0, !dictionary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let termsToUse = Array(dictionary.prefix(20))
            let promptText = "Technical instruction: " + termsToUse.joined(separator: ", ")
            let tokens = tokenizer.encode(text: " " + promptText)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
            print("[Transcription] Using \(options.promptTokens?.count ?? 0) prompt tokens (audio > 3s)")
        } else if let tokenizer = whisperKit.tokenizer {
            let promptText = "Technical instruction for software engineering:"
            let tokens = tokenizer.encode(text: " " + promptText)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
            print("[Transcription] Using minimal instructional prompt (audio <= 3s or no dictionary)")
        }

        let timeoutSeconds = max(30.0, audioDuration * 3.0)
        print("[Transcription] Timeout: \(String(format: "%.0f", timeoutSeconds))s")

        let transcriptionTask = Task {
            try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
        }

        let startTime = Date()

        let results: [TranscriptionResult]
        do {
            results = try await withTimeout(seconds: timeoutSeconds) {
                try await transcriptionTask.value
            }
        } catch is TimeoutError {
            transcriptionTask.cancel()
            print("[Transcription] TIMEOUT after \(String(format: "%.1f", timeoutSeconds))s")
            throw TranscriptionError.timeout
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("[Transcription] Completed in \(String(format: "%.2f", elapsed))s, \(results.count) segments")

        let rawText = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let filteredText = filterHallucinations(rawText)
        print("[Transcription] Final (\(filteredText.count) chars): \"\(filteredText.prefix(100))\"")

        return filteredText
    }

    /// Check if model files exist in WhisperKit's HuggingFace cache.
    /// Cache path: ~/.cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/
    private func isModelCached(_ model: WhisperModel) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cacheBase = home
            .appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml")
            .appendingPathComponent("snapshots")

        guard let snapshots = try? FileManager.default.contentsOfDirectory(
            at: cacheBase,
            includingPropertiesForKeys: nil
        ) else { return false }

        for snapshot in snapshots {
            let modelDir = snapshot.appendingPathComponent(model.rawValue)
            if FileManager.default.fileExists(atPath: modelDir.path) {
                return true
            }
        }
        return false
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        loadProgress = 0
        loadStatus = ""
        currentModel = ""
    }

    // MARK: - Hallucination Filter

    private static let hallucinationPatterns: [String] = [
        "thank you for watching",
        "thanks for watching",
        "subscribe to my channel",
        "please like and subscribe",
        "like and subscribe",
        "please subscribe",
        "see you in the next video",
        "see you next time",
        "don't forget to subscribe",
        "hit the bell",
        "hit the notification",
        "leave a comment",
        "share this video",
        "thanks for listening",
        "thank you for listening",
        "goodbye",
        "bye bye",
        "you",
    ]

    private func filterHallucinations(_ text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return "" }

        for pattern in Self.hallucinationPatterns {
            if lower == pattern || lower == pattern + "." {
                print("[Transcription] Filtered hallucination: \"\(text)\"")
                return ""
            }
        }

        // Detect repeated phrases (3+ repetitions)
        let words = lower.split(separator: " ")
        if words.count >= 6 {
            for n in 1...min(5, words.count / 3) {
                let ngrams = stride(from: 0, to: words.count - n + 1, by: n).map {
                    words[$0..<min($0 + n, words.count)].joined(separator: " ")
                }
                let first = ngrams.first ?? ""
                if !first.isEmpty && ngrams.allSatisfy({ $0 == first }) && ngrams.count >= 3 {
                    print("[Transcription] Filtered repeated n-gram: \"\(first)\" x\(ngrams.count)")
                    return ""
                }
            }
        }

        // Reject non-ASCII-only results for English transcription
        let asciiCount = text.unicodeScalars.filter { $0.isASCII }.count
        if asciiCount < text.unicodeScalars.count / 2 {
            print("[Transcription] Filtered non-ASCII result: \"\(text.prefix(50))\"")
            return ""
        }

        return text
    }
}

// MARK: - Timeout Helper

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed
    case emptyAudioBuffer
    case timeout

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model is not loaded"
        case .transcriptionFailed: return "Transcription failed"
        case .emptyAudioBuffer: return "No audio recorded"
        case .timeout: return "Transcription timed out"
        }
    }
}
