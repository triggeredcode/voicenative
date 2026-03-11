@preconcurrency import AVFoundation
import Observation

@Observable
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private(set) var isRecording = false
    private(set) var audioDuration: TimeInterval = 0
    
    private var recordingStartTime: Date?
    
    var onAudioChunk: (@Sendable ([Float]) -> Void)?
    
    func start() throws {
        guard !isRecording else { return }
        
        audioBuffer.removeAll()
        recordingStartTime = Date()
        
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: true
        )!
        
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        let ratio = Constants.Audio.sampleRate / nativeFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(Constants.Audio.bufferSize) * ratio)
        
        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.bufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let frameLength = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                
                self.audioBuffer.append(contentsOf: samples)
                self.onAudioChunk?(samples)
            }
        }
        
        try engine.start()
        isRecording = true
    }
    
    func stop() -> [Float] {
        guard isRecording else { return [] }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        
        if let startTime = recordingStartTime {
            audioDuration = Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil
        
        return audioBuffer
    }
    
    func reset() {
        audioBuffer.removeAll()
        audioDuration = 0
    }
}

enum AudioCaptureError: LocalizedError {
    case converterCreationFailed
    case engineStartFailed
    
    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
