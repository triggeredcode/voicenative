import AVFoundation
import AppKit
import Observation

@MainActor
@Observable
final class PermissionManager {
    enum PermissionStatus: Sendable {
        case notDetermined
        case granted
        case denied
    }
    
    private(set) var microphoneStatus: PermissionStatus = .notDetermined
    private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    private(set) var inputMonitoringStatus: PermissionStatus = .notDetermined
    
    var allPermissionsGranted: Bool {
        microphoneStatus == .granted &&
        accessibilityStatus == .granted &&
        inputMonitoringStatus == .granted
    }
    
    func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkInputMonitoringPermission()
    }
    
    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
        return granted
    }
    
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }
    
    func requestAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        checkAccessibilityPermission()
    }
    
    func checkInputMonitoringPermission() {
        let hasAccess = CGRequestListenEventAccess()
        inputMonitoringStatus = hasAccess ? .granted : .denied
    }
    
    func requestInputMonitoringPermission() {
        let hasAccess = CGRequestListenEventAccess()
        inputMonitoringStatus = hasAccess ? .granted : .denied
    }
    
    nonisolated func openSystemPreferences(for permission: SystemPreference) {
        let url: URL?
        
        switch permission {
        case .microphone:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
        
        if let url {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    enum SystemPreference: Sendable {
        case microphone
        case accessibility
        case inputMonitoring
    }
}
