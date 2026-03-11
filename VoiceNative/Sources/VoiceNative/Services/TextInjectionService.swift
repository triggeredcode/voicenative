import AppKit
import Carbon.HIToolbox

final class TextInjectionService {
    func inject(_ text: String, autoPaste: Bool) {
        copyToClipboard(text)
        
        if autoPaste {
            simulatePaste()
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
        
        keyDown?.post(tap: .cghidEventTap)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
