import Foundation
import Observation

@Observable
final class VADService {
    private var silenceStartTime: Date?
    private var calibrationSamples: [Float] = []
    private var noiseFloor: Float = 0.01
    private var isCalibrated = false
    
    var silenceTimeout: TimeInterval = Constants.VAD.defaultSilenceTimeout
    var sensitivity: VADSensitivity = .medium
    
    var onSilenceDetected: (() -> Void)?
    
    private(set) var currentEnergy: Float = 0
    private(set) var isSpeechDetected = false
    
    func processAudioChunk(_ samples: [Float]) {
        let energy = computeRMSEnergy(samples)
        currentEnergy = energy
        
        if !isCalibrated {
            calibrate(with: samples)
            return
        }
        
        let threshold = max(noiseFloor * 2, sensitivity.energyThreshold)
        let speechDetected = energy > threshold
        
        if speechDetected {
            isSpeechDetected = true
            silenceStartTime = nil
        } else {
            if isSpeechDetected {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let startTime = silenceStartTime,
                          Date().timeIntervalSince(startTime) >= silenceTimeout {
                    onSilenceDetected?()
                    reset()
                }
            }
        }
    }
    
    func reset() {
        silenceStartTime = nil
        isSpeechDetected = false
        currentEnergy = 0
    }
    
    func resetCalibration() {
        calibrationSamples.removeAll()
        noiseFloor = 0.01
        isCalibrated = false
        reset()
    }
    
    private func calibrate(with samples: [Float]) {
        calibrationSamples.append(contentsOf: samples)
        
        let calibrationSampleCount = Int(Constants.Audio.sampleRate * Constants.VAD.calibrationDuration)
        
        if calibrationSamples.count >= calibrationSampleCount {
            noiseFloor = computeRMSEnergy(calibrationSamples)
            isCalibrated = true
            calibrationSamples.removeAll()
        }
    }
    
    private func computeRMSEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
