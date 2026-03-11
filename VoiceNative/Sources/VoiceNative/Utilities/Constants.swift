import Foundation

enum Constants {
    static let appName = "VoiceNative"
    static let bundleIdentifier = "com.mochistack.voicenative"

    enum Audio {
        static let targetSampleRate: Double = 16000
        static let channels: UInt32 = 1
    }

    enum Hotkey {
        static let rightShiftKeyCode: UInt16 = 60
        static let leftShiftKeyCode: UInt16 = 56
        static let escapeKeyCode: UInt16 = 53
    }

    enum Recording {
        static let defaultMaxDuration: TimeInterval = 300 // 5 minutes
        static let minimumDurationForTranscription: TimeInterval = 0.3
    }

    enum VAD {
        static let windowDuration: TimeInterval = 0.1
        static let calibrationDuration: TimeInterval = 0.5
        static let defaultSilenceTimeout: TimeInterval = 3.0
        static let minimumRecordingBeforeVAD: TimeInterval = 3.0
    }

    enum MenuBarIcon {
        static let feedbackDuration: TimeInterval = 1.5
    }
}
