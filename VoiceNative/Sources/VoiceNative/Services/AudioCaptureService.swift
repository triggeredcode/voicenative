@preconcurrency import AVFoundation
import Observation

@Observable
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private(set) var isRecording = false
    private(set) var audioDuration: TimeInterval = 0
    
    private var recordingStartTime: Date?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    
    var onAudioChunk: (@Sendable ([Float]) -> Void)?
    
    func start() throws {
        guard !isRecording else {
            print("[AudioCapture] Already recording, ignoring start()")
            return
        }
        
        bufferLock.lock()
        audioBuffer.removeAll()
        audioBuffer.reserveCapacity(16000 * 60 * 2) // Pre-allocate for 2 minutes
        bufferLock.unlock()
        
        recordingStartTime = Date()
        
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        print("[AudioCapture] Native format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount) channels")
        
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: true
        )!
        
        guard let targetFormat else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        guard converter != nil else {
            print("[AudioCapture] ERROR: Failed to create converter")
            throw AudioCaptureError.converterCreationFailed
        }
        
        print("[AudioCapture] Target format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount) channels")
        
        let ratio = Constants.Audio.sampleRate / nativeFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(Constants.Audio.bufferSize) * ratio)
        
        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.bufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let targetFormat = self.targetFormat else { return }
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let error {
                print("[AudioCapture] Conversion error: \(error)")
                return
            }
            
            if let channelData = convertedBuffer.floatChannelData?[0] {
                let frameLength = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                let currentCount = self.audioBuffer.count
                self.bufferLock.unlock()
                
                // Log every ~5 seconds
                if currentCount % (16000 * 5) < frameLength {
                    let seconds = Double(currentCount) / 16000.0
                    print("[AudioCapture] Recording: \(String(format: "%.1f", seconds))s (\(currentCount) samples)")
                }
                
                self.onAudioChunk?(samples)
            }
        }
        
        try engine.start()
        isRecording = true
        print("[AudioCapture] Started recording")
    }
    
    func stop() -> [Float] {
        guard isRecording else {
            print("[AudioCapture] Not recording, ignoring stop()")
            return []
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        converter = nil
        
        if let startTime = recordingStartTime {
            audioDuration = Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil
        
        bufferLock.lock()
        let result = audioBuffer
        bufferLock.unlock()
        
        print("[AudioCapture] Stopped recording: \(result.count) samples (~\(String(format: "%.1f", audioDuration))s)")
        
        return result
    }
    
    func reset() {
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
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
