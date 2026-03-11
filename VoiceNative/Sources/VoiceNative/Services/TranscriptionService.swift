import Foundation
import WhisperKit
import Observation

@Observable
final class TranscriptionService: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var loadProgress: Double = 0
    private(set) var currentModel: String = ""
    
    func loadModel(_ model: WhisperModel) async throws {
        await MainActor.run {
            isModelLoaded = false
            loadProgress = 0
            currentModel = model.rawValue
        }
        
        let config = WhisperKitConfig(model: model.rawValue)
        whisperKit = try await WhisperKit(config)
        
        await MainActor.run {
            isModelLoaded = true
            loadProgress = 1.0
        }
    }
    
    func transcribe(audioBuffer: [Float], dictionary: [String] = []) async throws -> String {
        guard let whisperKit, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        
        await MainActor.run { isTranscribing = true }
        defer { Task { @MainActor in self.isTranscribing = false } }
        
        var options = DecodingOptions(task: .transcribe, language: "en")
        
        if !dictionary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let promptText = " " + dictionary.joined(separator: " ")
            let tokens = tokenizer.encode(text: promptText)
            options.promptTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        
        let results = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
        
        let transcription = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return transcription
    }
    
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        loadProgress = 0
        currentModel = ""
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
