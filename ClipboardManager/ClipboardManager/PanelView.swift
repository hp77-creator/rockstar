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
            ClipboardHistoryView(isInPanel: true, selectedIndex: $selectedIndex)
                .environmentObject(appState)
        }
        .frame(width: 300, height: 400)
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : .white)
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            // Reset selection when panel appears
            selectedIndex = 0
            
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: // Down arrow
                    if !appState.clips.isEmpty {
                        selectedIndex = min(selectedIndex + 1, appState.clips.count - 1)
                    }
                    return nil
                case 126: // Up arrow
                    if !appState.clips.isEmpty {
                        selectedIndex = max(selectedIndex - 1, 0)
                    }
                    return nil
                case 36, 76: // Return key or numpad enter
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
            // Get the current mouse location
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { screen in
                screen.frame.contains(mouseLocation)
            } ?? NSScreen.main ?? NSScreen.screens.first!
            
            // Convert mouse location to screen coordinates
            let screenFrame = screen.visibleFrame
            
            // Calculate panel position
            let panelWidth: CGFloat = 300
            let panelHeight: CGFloat = 400
            
            // Start with mouse position
            var panelX = mouseLocation.x - panelWidth/2
            var panelY = mouseLocation.y - panelHeight - 10 // 10px below cursor
            
            // Ensure panel stays within screen bounds
            if panelX + panelWidth > screenFrame.maxX {
                panelX = screenFrame.maxX - panelWidth - 10
            }
            if panelX < screenFrame.minX {
                panelX = screenFrame.minX + 10
            }
            if panelY + panelHeight > screenFrame.maxY {
                panelY = screenFrame.maxY - panelHeight - 10
            }
            if panelY < screenFrame.minY {
                panelY = screenFrame.minY + 10
            }
            
            let panelRect = NSRect(
                x: panelX,
                y: panelY,
                width: panelWidth,
                height: panelHeight
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
