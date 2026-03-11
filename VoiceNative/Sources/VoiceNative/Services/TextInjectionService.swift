import AppKit
import Carbon.HIToolbox

@MainActor
final class TextInjectionService {
    func inject(_ text: String, autoPaste: Bool, targetApp: NSRunningApplication? = nil) {
        copyToClipboard(text)

        guard autoPaste else { return }

        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate()
            print("[Paste] Activating \(app.localizedName ?? "unknown") before paste")
        }

        // Give the target app time to come to front, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()
        }
    }

    nonisolated func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            print("[Paste] Failed to create CGEvents (Accessibility permission missing?)")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(10_000) // 10ms between down/up
        keyUp.post(tap: .cghidEventTap)
        print("[Paste] Simulated Cmd+V")
    }
}
