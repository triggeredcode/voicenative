import Foundation
import WhisperKit
import Observation

@Observable
final class TranscriptionService: @unchecked Sendable {
    private var whisperKit: WhisperKit?

    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var isLoading = false
    private(set) var loadProgress: Double = 0
    private(set) var loadStatus: String = ""
    private(set) var currentModel: String = ""

    // MARK: - Model Loading

    @MainActor
    func loadModel(_ model: WhisperModel) async throws {
        guard !isLoading else {
            print("[Transcription] loadModel already in progress, skipping")
            return
        }

        if isModelLoaded, currentModel == model.rawValue, whisperKit != nil {
            print("[Transcription] Model \(model.rawValue) already loaded, skipping")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let cachedPath = modelCachePath(model)
        let cached = cachedPath != nil
        let loadStart = CFAbsoluteTimeGetCurrent()

        isModelLoaded = false
        loadProgress = 0
        loadStatus = cached ? "Loading model..." : "Downloading model (~\(model.sizeEstimate))..."
        currentModel = model.rawValue

        print("[Transcription] Loading model: \(model.rawValue) (cached: \(cached))")

        // GPU for encoder allows pipeline parallelism with ANE decoder across chunks
        let compute = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly
        )

        let config: WhisperKitConfig
        if let folder = cachedPath {
            config = WhisperKitConfig(
                modelFolder: folder,
                computeOptions: compute,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
        } else {
            config = WhisperKitConfig(
                model: model.rawValue,
                computeOptions: compute,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: true
            )
        }

        whisperKit = try await WhisperKit(config)

        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart

        isModelLoaded = true
        loadProgress = 1.0
        loadStatus = "Ready"

        print("[Transcription] Model loaded in \(String(format: "%.2f", loadTime))s (cached: \(cached))")
    }

    func ensureModelReady(_ model: WhisperModel) async throws {
        guard let wk = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let state = wk.modelState
        if state == .loaded || state == .prewarmed {
            return
        }

        print("[Transcription] Model state is \(state), reloading in-place...")
        let t0 = CFAbsoluteTimeGetCurrent()
        try await wk.loadModels()
        await MainActor.run { self.isModelLoaded = true }
        print("[Transcription] Model reloaded in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
    }

    /// Run a micro-inference to keep CoreML/ANE pipeline warm.
    func prewarm() async {
        guard let whisperKit, isModelLoaded, !isTranscribing, !isLoading else { return }
        let silence = [Float](repeating: 0, count: 8000)
        let options = DecodingOptions(task: .transcribe, language: "en", withoutTimestamps: true, suppressBlank: true)
        let t0 = CFAbsoluteTimeGetCurrent()
        print("[Transcription] Prewarm: micro-inference...")
        _ = try? await whisperKit.transcribe(audioArray: silence, decodeOptions: options)
        print("[Transcription] Prewarm done (\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s)")
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

        isTranscribing = true
        defer { isTranscribing = false }

        let useChunking = sampleCount > 480_000
        var options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 0,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true,
            chunkingStrategy: useChunking ? .vad : nil
        )

        // Lightweight technical prompt -- biases decoder toward code/engineering terms
        if let tokenizer = whisperKit.tokenizer {
            let prompt = "Technical software engineering dictation."
            let tokens = tokenizer.encode(text: " " + prompt)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }

        if useChunking {
            print("[Transcription] VAD chunking enabled for \(String(format: "%.0f", audioDuration))s audio")
        }

        let timeoutSeconds = max(30.0, audioDuration * 2.0)

        let transcriptionTask = Task {
            try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

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

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let rtf = elapsed / audioDuration
        print("[Transcription] Done in \(String(format: "%.2f", elapsed))s (\(results.count) segments, RTF=\(String(format: "%.3f", rtf)))")

        let rawText = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let filteredText = filterHallucinations(rawText)
        print("[Transcription] Result (\(filteredText.count) chars): \"\(filteredText.prefix(200))\"")

        return filteredText
    }

    /// Transcribe a single chunk during recording. Lighter than full transcribe -- no timeout, no hallucination filter.
    func transcribeChunk(audioBuffer: [Float], audioDuration: TimeInterval) async throws -> String {
        guard let whisperKit, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        guard !audioBuffer.isEmpty else { return "" }

        var options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 0,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )

        if let tokenizer = whisperKit.tokenizer {
            let prompt = "Technical software engineering dictation."
            let tokens = tokenizer.encode(text: " " + prompt)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }

        let results = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
        return results.compactMap(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the cached model folder path if it exists, nil otherwise.
    private func modelCachePath(_ model: WhisperModel) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let modelDir = home
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(model.rawValue)
        guard fm.fileExists(atPath: modelDir.path) else { return nil }
        return modelDir.path
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
