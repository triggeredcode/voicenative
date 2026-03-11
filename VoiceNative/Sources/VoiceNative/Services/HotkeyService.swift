import Foundation
import CoreGraphics
import AppKit
import Observation

@Observable
final class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private(set) var isListening = false
    private(set) var isKeyPressed = false
    
    var triggerKeyCode: UInt16 = Constants.Hotkey.rightShiftKeyCode
    var triggerMode: TriggerMode = .toggle
    
    var onTriggerStart: (() -> Void)?
    var onTriggerEnd: (() -> Void)?
    
    private var callbackWrapper: HotkeyCallbackWrapper?
    
    func startListening() {
        guard !isListening else { return }
        
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        callbackWrapper = HotkeyCallbackWrapper(service: self)
        let userInfo = Unmanaged.passUnretained(callbackWrapper!).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
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
        
        eventTap = nil
        runLoopSource = nil
        callbackWrapper = nil
        isListening = false
    }
    
    private func fallbackToGlobalMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        isListening = true
    }
    
    fileprivate func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        
        guard keyCode == triggerKeyCode else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        
        switch triggerMode {
        case .toggle:
            if isShiftPressed && !isKeyPressed {
                isKeyPressed = true
                onTriggerStart?()
            } else if !isShiftPressed && isKeyPressed {
                isKeyPressed = false
            }
            
        case .holdToTalk:
            if isShiftPressed && !isKeyPressed {
                isKeyPressed = true
                onTriggerStart?()
            } else if !isShiftPressed && isKeyPressed {
                isKeyPressed = false
                onTriggerEnd?()
            }
        }
    }
    
    func simulateToggleEnd() {
        if triggerMode == .toggle && isKeyPressed {
            isKeyPressed = false
            onTriggerEnd?()
        }
    }
}

private class HotkeyCallbackWrapper {
    weak var service: HotkeyService?
    
    init(service: HotkeyService) {
        self.service = service
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    
    let wrapper = Unmanaged<HotkeyCallbackWrapper>.fromOpaque(userInfo).takeUnretainedValue()
    
    if let nsEvent = NSEvent(cgEvent: event) {
        wrapper.service?.handleFlagsChanged(nsEvent)
    }
    
    return Unmanaged.passRetained(event)
}
