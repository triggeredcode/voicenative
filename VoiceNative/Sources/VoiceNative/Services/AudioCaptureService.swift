@preconcurrency import AVFoundation
import Accelerate
import Observation

@Observable
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var rawBuffer: [Float] = []
    private let bufferLock = NSLock()
    private(set) var isRecording = false
    private(set) var audioDuration: TimeInterval = 0

    private var recordingStartTime: Date?
    private var nativeSampleRate: Double = 48000

    var onAudioChunk: (@Sendable ([Float]) -> Void)?

    func start() throws {
        guard !isRecording else { return }

        bufferLock.lock()
        rawBuffer.removeAll(keepingCapacity: true)
        rawBuffer.reserveCapacity(Int(48000) * 300) // 5 minutes at 48kHz
        bufferLock.unlock()

        recordingStartTime = Date()
        audioDuration = 0

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        nativeSampleRate = nativeFormat.sampleRate

        print("[AudioCapture] Native format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }

            let frameCount = Int(buffer.frameLength)
            let samples: [Float]

            if nativeFormat.channelCount > 1 {
                // Downmix to mono by averaging channels
                var mono = [Float](repeating: 0, count: frameCount)
                let channelCount = Int(nativeFormat.channelCount)
                for ch in 0..<channelCount {
                    let chData = buffer.floatChannelData![ch]
                    for i in 0..<frameCount {
                        mono[i] += chData[i]
                    }
                }
                let scale = 1.0 / Float(channelCount)
                for i in 0..<frameCount { mono[i] *= scale }
                samples = mono
            } else {
                samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
            }

            self.bufferLock.lock()
            self.rawBuffer.append(contentsOf: samples)
            let currentCount = self.rawBuffer.count
            self.bufferLock.unlock()

            if currentCount % (Int(self.nativeSampleRate) * 5) < frameCount {
                let seconds = Double(currentCount) / self.nativeSampleRate
                print("[AudioCapture] Recording: \(String(format: "%.1f", seconds))s (\(currentCount) samples @ \(Int(self.nativeSampleRate))Hz)")
            }

            self.onAudioChunk?(samples)
        }

        try engine.start()
        isRecording = true
        print("[AudioCapture] Started recording")
    }

    /// Stop recording and return 16kHz mono Float32 samples ready for WhisperKit.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        let t0 = CFAbsoluteTimeGetCurrent()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRecording = false

        if let startTime = recordingStartTime {
            audioDuration = Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil

        bufferLock.lock()
        let rawSamples = rawBuffer
        rawBuffer.removeAll(keepingCapacity: false)
        bufferLock.unlock()

        let rawDuration = Double(rawSamples.count) / nativeSampleRate
        print("[AudioCapture] Stopped: \(rawSamples.count) raw samples (~\(String(format: "%.1f", rawDuration))s)")

        let t1 = CFAbsoluteTimeGetCurrent()
        let resampled: [Float]
        if nativeSampleRate == Constants.Audio.targetSampleRate {
            resampled = rawSamples
        } else {
            resampled = convertToTargetRate(rawSamples)
        }
        let t2 = CFAbsoluteTimeGetCurrent()

        let normalized = normalizeAudio(resampled)
        let t3 = CFAbsoluteTimeGetCurrent()

        print("[AudioCapture] Processing: resample=\(String(format: "%.3f", t2-t1))s, normalize=\(String(format: "%.3f", t3-t2))s, total=\(String(format: "%.3f", t3-t0))s -> \(normalized.count) samples")
        return normalized
    }

    func reset() {
        bufferLock.lock()
        rawBuffer.removeAll(keepingCapacity: false)
        bufferLock.unlock()
        audioDuration = 0
    }

    /// Returns the current recording duration based on buffer size at native rate.
    var currentRecordingDuration: TimeInterval {
        if isRecording, let start = recordingStartTime {
            return Date().timeIntervalSince(start)
        }
        return 0
    }

    // MARK: - Audio Processing (Accelerate/vDSP)

    /// Peak-normalize using vDSP for SIMD speed. Target peak 0.95, max gain 20x.
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        guard peak > 0 else { return samples }

        var scale = min(0.95 / peak, 20.0)
        if scale > 0.99 && scale < 1.01 { return samples }

        print("[AudioCapture] Normalizing: peak=\(String(format: "%.4f", peak)), gain=\(String(format: "%.1f", scale))x")
        var result = [Float](repeating: 0, count: samples.count)
        vDSP_vsmul(samples, 1, &scale, &result, 1, vDSP_Length(samples.count))
        return result
    }

    // MARK: - Resampling

    /// Non-real-time conversion of the full buffer from native rate to 16kHz mono.
    private func convertToTargetRate(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }

        let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeSampleRate,
            channels: 1,
            interleaved: true
        )!

        let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.targetSampleRate,
            channels: 1,
            interleaved: true
        )!

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            print("[AudioCapture] ERROR: Could not create converter, returning raw samples")
            return input
        }

        let inputFrameCount = AVAudioFrameCount(input.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: inputFrameCount) else {
            return input
        }
        inputBuffer.frameLength = inputFrameCount
        memcpy(inputBuffer.floatChannelData![0], input, input.count * MemoryLayout<Float>.size)

        let ratio = Constants.Audio.targetSampleRate / nativeSampleRate
        let outputFrameCount = AVAudioFrameCount(ceil(Double(input.count) * ratio)) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outputFrameCount) else {
            return input
        }

        nonisolated(unsafe) var inputConsumed = false
        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let convError {
            print("[AudioCapture] Conversion error: \(convError)")
            return input
        }

        guard let outData = outputBuffer.floatChannelData?[0] else { return input }
        return Array(UnsafeBufferPointer(start: outData, count: Int(outputBuffer.frameLength)))
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
