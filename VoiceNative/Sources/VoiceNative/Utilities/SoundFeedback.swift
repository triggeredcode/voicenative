import AppKit

enum SoundFeedback {
    static func playStartRecording() {
        NSSound(named: .init("Tink"))?.play()
    }

    static func playStopRecording() {
        NSSound(named: .init("Pop"))?.play()
    }

    static func playCopied() {
        NSSound(named: .init("Glass"))?.play()
    }

    static func playError() {
        NSSound(named: .init("Basso"))?.play()
    }

    static func playCancelled() {
        NSSound(named: .init("Funk"))?.play()
    }

    static func playNoSpeech() {
        NSSound(named: .init("Purr"))?.play()
    }
}
