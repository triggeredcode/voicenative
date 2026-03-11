import SwiftUI
import Observation

@Observable
final class AppState {
    enum Phase: String, Equatable {
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
    
    func startListening() {
        guard phase == .ready else { return }
        phase = .listening
    }
    
    func stopListening() {
        guard phase == .listening else { return }
        phase = .processing
    }
    
    func completeTranscription(_ text: String) {
        lastTranscription = text
        phase = .ready
    }
    
    func setError(_ message: String) {
        errorMessage = message
        phase = .error
    }
    
    func setReady() {
        errorMessage = nil
        phase = .ready
    }
}
