import Foundation
import CoreGraphics
import AppKit
import Observation

@Observable
final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private(set) var isListening = false
    private var isKeyDown = false
    private(set) var isToggleActive = false

    var triggerKeyCode: UInt16 = Constants.Hotkey.rightShiftKeyCode
    var triggerMode: TriggerMode = .toggle

    var onTriggerStart: (() -> Void)?
    var onTriggerEnd: (() -> Void)?
    var onCancel: (() -> Void)?

    func startListening() {
        guard !isListening else { return }

        // Catches events directed at OTHER apps
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
        }

        // Catches events in OUR app (menu bar popover, settings window, etc.)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        isListening = true
        print("[HotkeyService] Listening via global+local monitors (keyCode=\(triggerKeyCode), mode=\(triggerMode))")
    }

    func stopListening() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isListening = false
        isKeyDown = false
        isToggleActive = false
    }

    /// Call when recording starts externally (UI button) so next Shift press is a STOP
    func markToggleActive() {
        isToggleActive = true
    }

    func resetToggleState() {
        isToggleActive = false
        isKeyDown = false
    }

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == Constants.Hotkey.escapeKeyCode {
            onCancel?()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard keyCode == triggerKeyCode else { return }

        let isModifierPressed = event.modifierFlags.contains(.shift)

        switch triggerMode {
        case .toggle:
            if isModifierPressed && !isKeyDown {
                isKeyDown = true
                if !isToggleActive {
                    isToggleActive = true
                    print("[HotkeyService] Toggle START (keyCode=\(keyCode))")
                    onTriggerStart?()
                } else {
                    isToggleActive = false
                    print("[HotkeyService] Toggle STOP (keyCode=\(keyCode))")
                    onTriggerEnd?()
                }
            } else if !isModifierPressed {
                isKeyDown = false
            }

        case .holdToTalk:
            if isModifierPressed && !isKeyDown {
                isKeyDown = true
                print("[HotkeyService] Hold START (keyCode=\(keyCode))")
                onTriggerStart?()
            } else if !isModifierPressed && isKeyDown {
                isKeyDown = false
                print("[HotkeyService] Hold STOP (keyCode=\(keyCode))")
                onTriggerEnd?()
            }
        }
    }
}
