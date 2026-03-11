import Foundation
import CoreGraphics
import AppKit
import Observation

@Observable
final class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var retainedWrapper: Unmanaged<HotkeyCallbackWrapper>?

    private(set) var isListening = false
    private var isKeyDown = false
    private var isToggleActive = false

    var triggerKeyCode: UInt16 = Constants.Hotkey.rightShiftKeyCode
    var triggerMode: TriggerMode = .toggle

    var onTriggerStart: (() -> Void)?
    var onTriggerEnd: (() -> Void)?
    var onCancel: (() -> Void)?

    func startListening() {
        guard !isListening else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let wrapper = HotkeyCallbackWrapper(service: self)
        let retained = Unmanaged.passRetained(wrapper)
        retainedWrapper = retained

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            retainedWrapper = nil
            fallbackToGlobalMonitor()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
    }

    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        retainedWrapper?.release()
        retainedWrapper = nil
        eventTap = nil
        runLoopSource = nil
        isListening = false
        isKeyDown = false
        isToggleActive = false
    }

    func resetToggleState() {
        isToggleActive = false
        isKeyDown = false
    }

    private func fallbackToGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyDown(event)
            } else {
                self?.handleFlagsChanged(event)
            }
        }
        isListening = true
    }

    fileprivate func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == Constants.Hotkey.escapeKeyCode {
            onCancel?()
        }
    }

    fileprivate func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard keyCode == triggerKeyCode else { return }

        let isModifierPressed = event.modifierFlags.contains(.shift)

        switch triggerMode {
        case .toggle:
            if isModifierPressed && !isKeyDown {
                isKeyDown = true
                if !isToggleActive {
                    isToggleActive = true
                    onTriggerStart?()
                } else {
                    isToggleActive = false
                    onTriggerEnd?()
                }
            } else if !isModifierPressed {
                isKeyDown = false
            }

        case .holdToTalk:
            if isModifierPressed && !isKeyDown {
                isKeyDown = true
                onTriggerStart?()
            } else if !isModifierPressed && isKeyDown {
                isKeyDown = false
                onTriggerEnd?()
            }
        }
    }

    fileprivate func handleTapDisabled() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyService] Re-enabled event tap after system disabled it")
    }
}

private class HotkeyCallbackWrapper {
    weak var service: HotkeyService?
    init(service: HotkeyService) { self.service = service }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let wrapper = Unmanaged<HotkeyCallbackWrapper>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        wrapper.service?.handleTapDisabled()
        return Unmanaged.passRetained(event)
    default:
        break
    }

    if let nsEvent = NSEvent(cgEvent: event) {
        if type == .keyDown {
            wrapper.service?.handleKeyDown(nsEvent)
        } else {
            wrapper.service?.handleFlagsChanged(nsEvent)
        }
    }

    return Unmanaged.passRetained(event)
}
