import SwiftUI
import AppKit

class ClipboardPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isFloatingPanel = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        
        // Close panel when it loses focus
        self.hidesOnDeactivate = true
    }
    
    // Override to enable clicking through the panel
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

struct PanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0
    
    var body: some View {
        VStack(spacing: 0) {
            ClipboardHistoryView(isInPanel: true)
                .environmentObject(appState)
        }
        .frame(width: 300, height: 400)
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : .white)
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: // Down arrow
                    selectedIndex = min(selectedIndex + 1, appState.clips.count - 1)
                    return nil
                case 126: // Up arrow
                    selectedIndex = max(selectedIndex - 1, 0)
                    return nil
                case 36: // Return key
                    if !appState.clips.isEmpty {
                        appState.pasteClip(at: selectedIndex)
                        PanelWindowManager.hidePanel()
                    }
                    return nil
                case 53: // Escape key
                    PanelWindowManager.hidePanel()
                    return nil
                default:
                    return event
                }
            }
        }
    }
}

// Helper view to manage panel window
struct PanelWindowManager {
    private static var panel: ClipboardPanel?
    
    static func showPanel(with appState: AppState) {
        if panel == nil {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            let panelRect = NSRect(
                x: screen.midX - 150,
                y: screen.midY - 200,
                width: 300,
                height: 400
            )
            panel = ClipboardPanel(contentRect: panelRect)
            
            let hostingView = NSHostingView(
                rootView: PanelView()
                    .environmentObject(appState)
            )
            panel?.contentView = hostingView
        }
        
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static func hidePanel() {
        panel?.orderOut(nil)
    }
    
    static func togglePanel(with appState: AppState) {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel(with: appState)
        }
    }
}
