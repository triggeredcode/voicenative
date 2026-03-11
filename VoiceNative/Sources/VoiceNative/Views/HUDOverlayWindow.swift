import SwiftUI
import AppKit

@MainActor
final class HUDOverlayController {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    
    var position: HUDPosition = .topCenter
    var opacity: Double = 0.85
    
    func show(state: HUDState) {
        dismissTask?.cancel()
        
        guard position != .off else { return }
        
        if window == nil {
            createWindow()
        }
        
        updateContent(state: state)
        positionWindow()
        
        window?.alphaValue = opacity
        window?.orderFrontRegardless()
        
        if state == .copied {
            scheduleDismiss()
        }
    }
    
    func hide() {
        dismissTask?.cancel()
        window?.close()
        window = nil
    }
    
    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.HUD.defaultWidth, height: Constants.HUD.defaultHeight),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        window = panel
    }
    
    private func updateContent(state: HUDState) {
        let contentView = HUDContentView(state: state)
        window?.contentView = NSHostingView(rootView: contentView)
    }
    
    private func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        var origin: NSPoint
        
        switch position {
        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowFrame.width / 2,
                y: screenFrame.maxY - windowFrame.height - 100
            )
        case .nearCursor:
            let mouseLocation = NSEvent.mouseLocation
            origin = NSPoint(
                x: mouseLocation.x - windowFrame.width / 2,
                y: mouseLocation.y + 30
            )
        case .off:
            return
        }
        
        window.setFrameOrigin(origin)
    }
    
    private func scheduleDismiss() {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.HUD.dismissDelay))
            self.hide()
        }
    }
}

enum HUDState {
    case listening
    case processing
    case copied
    
    var icon: String {
        switch self {
        case .listening:
            return "mic.fill"
        case .processing:
            return "ellipsis.circle"
        case .copied:
            return "checkmark.circle.fill"
        }
    }
    
    var text: String {
        switch self {
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .copied:
            return "Copied"
        }
    }
    
    var color: Color {
        switch self {
        case .listening:
            return .red
        case .processing:
            return .orange
        case .copied:
            return .green
        }
    }
}

struct HUDContentView: View {
    let state: HUDState
    
    var body: some View {
        HStack(spacing: 10) {
            if state == .listening {
                PulsingCircle()
            } else if state == .processing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: state.icon)
                    .foregroundStyle(state.color)
            }
            
            Text(state.text)
                .font(.system(.body, design: .rounded, weight: .medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }
}

struct PulsingCircle: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

#Preview("Listening") {
    HUDContentView(state: .listening)
        .padding()
}

#Preview("Processing") {
    HUDContentView(state: .processing)
        .padding()
}

#Preview("Copied") {
    HUDContentView(state: .copied)
        .padding()
}
