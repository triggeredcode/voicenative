import AppKit
import Carbon.HIToolbox

@MainActor
final class TextInjectionService {
    func inject(_ text: String, autoPaste: Bool) {
        let pasteboard = NSPasteboard.general

        let previousString = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        copyToClipboard(text)

        if autoPaste {
            simulatePaste()

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard pasteboard.changeCount == previousChangeCount + 1 else { return }
                if let previous = previousString {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    nonisolated func copyToClipboard(_ text: String) {
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

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            keyDown?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(10))
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
