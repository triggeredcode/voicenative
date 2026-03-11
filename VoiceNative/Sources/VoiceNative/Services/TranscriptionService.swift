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
    
    func loadModel(_ model: WhisperModel, modelManager: ModelManager) async throws {
        await MainActor.run {
            isModelLoaded = false
            loadProgress = 0
            loadStatus = "Checking model..."
            currentModel = model.rawValue
        }
        
        let modelFolder: URL
        if let existingFolder = await modelManager.modelFolderPath(for: model) {
            modelFolder = existingFolder
            await MainActor.run {
                loadStatus = "Model found locally"
                loadProgress = 0.1
            }
        } else {
            await MainActor.run {
                loadStatus = "Downloading model..."
            }
            modelFolder = try await modelManager.downloadModel(model)
            await MainActor.run {
                loadProgress = 0.5
            }
        }
        
        await MainActor.run {
            loadStatus = "Loading model into memory..."
            loadProgress = 0.6
        }
        
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true
        )
        
        whisperKit = try await WhisperKit(config)
        
        await MainActor.run {
            isModelLoaded = true
            loadProgress = 1.0
            loadStatus = "Ready"
        }
    }
    
    func loadModelDirect(_ modelName: String) async throws {
        await MainActor.run {
            isModelLoaded = false
            loadProgress = 0
            loadStatus = "Downloading and loading model..."
            currentModel = modelName
        }
        
        let config = WhisperKitConfig(
            model: modelName,
            verbose: true,
            logLevel: .info,
            prewarm: true,
            load: true,
            download: true
        )
        
        whisperKit = try await WhisperKit(config)
        
        await MainActor.run {
            isModelLoaded = true
            loadProgress = 1.0
            loadStatus = "Ready"
        }
    }
    
    func transcribe(audioBuffer: [Float], dictionary: [String] = []) async throws -> String {
        guard let whisperKit, isModelLoaded else {
            print("[TranscriptionService] ERROR: Model not loaded")
            throw TranscriptionError.modelNotLoaded
        }
        
        let sampleCount = audioBuffer.count
        let durationSeconds = Double(sampleCount) / 16000.0
        print("[TranscriptionService] Starting transcription: \(sampleCount) samples (~\(String(format: "%.1f", durationSeconds))s of audio)")
        
        guard sampleCount > 0 else {
            print("[TranscriptionService] ERROR: Empty audio buffer")
            throw TranscriptionError.emptyAudioBuffer
        }
        
        await MainActor.run { isTranscribing = true }
        defer { Task { @MainActor in self.isTranscribing = false } }
        
        var options = DecodingOptions(task: .transcribe, language: "en")
        
        if !dictionary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let promptText = " " + dictionary.joined(separator: " ")
            let tokens = tokenizer.encode(text: promptText)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
            print("[TranscriptionService] Using \(options.promptTokens?.count ?? 0) prompt tokens")
        }
        
        print("[TranscriptionService] Calling WhisperKit.transcribe()...")
        let startTime = Date()
        
        let results = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("[TranscriptionService] Transcription completed in \(String(format: "%.2f", elapsed))s")
        print("[TranscriptionService] Got \(results.count) result segments")
        
        let transcription = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        print("[TranscriptionService] Final text (\(transcription.count) chars): \"\(transcription.prefix(100))...\"")
        
        return transcription
    }
    
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        loadProgress = 0
        loadStatus = ""
        currentModel = ""
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed
    case downloadFailed(String)
    case emptyAudioBuffer
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .transcriptionFailed:
            return "Transcription failed"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .emptyAudioBuffer:
            return "No audio recorded"
        }
    }
}
