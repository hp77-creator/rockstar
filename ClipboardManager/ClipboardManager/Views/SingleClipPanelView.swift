import SwiftUI
import AppKit

struct SingleClipPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0
    @State private var autopasteTimer: Timer?
    
    private func simulatePaste() {
        Logger.debug("Simulating paste...")
        
        if let previousApp = SingleClipPanelManager.previousApp {
            Logger.debug("Found stored previous app: \(previousApp.localizedName ?? "unknown")")
            
            // Hide our panel first
            SingleClipPanelManager.hidePanel()
            
            // Activate the previous app with focus
            let activated = previousApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            Logger.debug("Activated previous app: \(activated)")
            
            // Small delay to ensure app is active
            Thread.sleep(forTimeInterval: 0.1)
            
            // Create and post the paste events
            let source = CGEventSource(stateID: .hidSystemState)
            
            let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            vKeyDown?.flags = .maskCommand
            vKeyDown?.post(tap: .cghidEventTap)
            
            Thread.sleep(forTimeInterval: 0.05)
            
            let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vKeyUp?.flags = .maskCommand
            vKeyUp?.post(tap: .cghidEventTap)
            
            Logger.debug("Paste events posted")
        } else {
            Logger.error("No previous app stored")
            SingleClipPanelManager.hidePanel()
        }
    }
    
    private func resetIdleTimer() {
        Logger.debug("Resetting idle timer...")
        autopasteTimer?.invalidate()
        autopasteTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Logger.debug("Idle timer fired - user has been idle for 3 seconds")
            if !appState.clips.isEmpty {
                Task {
                    do {
                        Logger.debug("Setting clipboard content...")
                        try await appState.pasteClip(at: selectedIndex)
                        
                        // Add a small delay to ensure clipboard is set
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        
                        DispatchQueue.main.async {
                            Logger.debug("Executing paste command...")
                            simulatePaste()
                        }
                    } catch {
                        Logger.error("Failed to paste clip: \(error)")
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if !appState.clips.isEmpty {
                let clip = appState.clips[selectedIndex]
                ClipboardItemContentView(
                    type: clip.type,
                    content: clip.content,
                    contentString: clip.contentString
                )
                .padding()
                .frame(maxWidth: CGFloat.infinity, maxHeight: 200, alignment: .leading)
                
                HStack {
                    Text("\(selectedIndex + 1) of \(appState.clips.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Use ←→ to navigate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 400, height: 250)
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : .white)
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            selectedIndex = 0
            resetIdleTimer()
            
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 123: // Left arrow
                    if !appState.clips.isEmpty {
                        selectedIndex = max(selectedIndex - 1, 0)
                        resetIdleTimer()
                    }
                    return nil
                case 124: // Right arrow
                    if !appState.clips.isEmpty {
                        selectedIndex = min(selectedIndex + 1, appState.clips.count - 1)
                        resetIdleTimer()
                    }
                    return nil
                case 36, 76: // Return key or numpad enter
                    if !appState.clips.isEmpty {
                        Task {
                            do {
                                try await appState.pasteClip(at: selectedIndex)
                                DispatchQueue.main.async {
                                    simulatePaste()
                                }
                            } catch {
                                print("Failed to paste clip: \(error)")
                            }
                        }
                    }
                    return nil
                case 53: // Escape key
                    DispatchQueue.main.async {
                        SingleClipPanelManager.hidePanel()
                    }
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            autopasteTimer?.invalidate()
            autopasteTimer = nil
        }
    }
}

class SingleClipPanel: NSPanel {
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
        self.hidesOnDeactivate = true
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct SingleClipPanelManager {
    private static var panel: SingleClipPanel?
    static var previousApp: NSRunningApplication?
    
    static func showPanel(with appState: AppState) {
        DispatchQueue.main.async {
            // Store the currently active app before showing our panel
            previousApp = NSWorkspace.shared.frontmostApplication
            Logger.debug("Storing previous app: \(previousApp?.localizedName ?? "unknown")")
            
            if panel == nil {
                let mouseLocation = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { screen in
                    screen.frame.contains(mouseLocation)
                } ?? NSScreen.main ?? NSScreen.screens.first!
                
                let screenFrame = screen.visibleFrame
                let panelWidth: CGFloat = 400
                let panelHeight: CGFloat = 250
                
                var panelX = mouseLocation.x - panelWidth/2
                var panelY = mouseLocation.y - panelHeight - 10
                
                // Keep panel within screen bounds
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
                
                panel = SingleClipPanel(contentRect: panelRect)
                panel?.contentView = NSHostingView(
                    rootView: SingleClipPanelView()
                        .environmentObject(appState)
                )
            }
            
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    static func hidePanel() {
        DispatchQueue.main.async {
            if let panel = panel {
                panel.orderOut(nil)
            }
        }
    }
    
    static func togglePanel(with appState: AppState) {
        DispatchQueue.main.async {
            if panel?.isVisible == true {
                hidePanel()
            } else {
                showPanel(with: appState)
            }
        }
    }
}
