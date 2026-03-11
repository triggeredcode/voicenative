import Foundation

enum Constants {
    static let appName = "VoiceNative"
    static let bundleIdentifier = "com.mochistack.voicenative"
    
    enum Audio {
        static let sampleRate: Double = 16000
        static let channels: UInt32 = 1
        static let bufferSize: UInt32 = 1024
    }
    
    enum Hotkey {
        static let rightShiftKeyCode: UInt16 = 60
        static let leftShiftKeyCode: UInt16 = 56
    }
    
    enum HUD {
        static let defaultWidth: CGFloat = 200
        static let defaultHeight: CGFloat = 50
        static let dismissDelay: TimeInterval = 1.5
        static let cornerRadius: CGFloat = 12
    }
    
    enum VAD {
        static let windowDuration: TimeInterval = 0.1
        static let calibrationDuration: TimeInterval = 0.5
        static let defaultSilenceTimeout: TimeInterval = 1.5
    }
}
