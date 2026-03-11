import AppKit

enum SoundFeedback {
    static func playStartRecording() {
        NSSound(named: .init("Tink"))?.play()
    }

    static func playStopRecording() {
        // Silent -- the transition to processing is visual feedback enough
    }

    static func playCopied() {
        NSSound(named: .init("Submarine"))?.play()
    }

    static func playError() {
        NSSound(named: .init("Purr"))?.play()
    }

    static func playCancelled() {
        // Silent -- icon X feedback only
    }

    static func playNoSpeech() {
        // Silent -- icon feedback only
    }
}
