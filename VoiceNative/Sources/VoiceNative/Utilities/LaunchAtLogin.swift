import ServiceManagement
import Observation

@MainActor
@Observable
final class LaunchAtLoginManager {
    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
            }
        }
    }
    
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
