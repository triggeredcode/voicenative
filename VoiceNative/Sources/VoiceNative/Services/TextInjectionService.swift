import AppKit
import Carbon.HIToolbox

final class TextInjectionService {
    func inject(_ text: String, autoPaste: Bool) {
        let pasteboard = NSPasteboard.general

        // Preserve existing clipboard contents
        let previousString = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        copyToClipboard(text)

        if autoPaste {
            simulatePaste()

            // Restore previous clipboard after paste has time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Only restore if clipboard hasn't been changed by something else
                guard pasteboard.changeCount == previousChangeCount + 1 else { return }
                if let previous = previousString {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        // 50ms delay to ensure clipboard is ready (Electron apps need this)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyDown?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                keyUp?.post(tap: .cghidEventTap)
            }
        }
    }
}
