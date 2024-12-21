import SwiftUI
import AppKit

@main
struct ClipboardManagerApp: App {
    // Keep strong reference to NSApplication
    private let app = NSApplication.shared
    @StateObject private var appState = AppState()
    
    init() {
        print("ClipboardManagerApp initializing...")
        
        // Request accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility permissions granted:", trusted)
        
        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "Please grant accessibility access in System Preferences > Security & Privacy > Privacy > Accessibility to enable keyboard shortcuts."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "Later")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        
        // Set up termination notification observer
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [appState] _ in
            print("Application will terminate, cleaning up...")
            appState.cleanup()
        }
    }
    
    var body: some Scene {
        MenuBarExtra("Clipboard Manager", systemImage: "clipboard") {
            VStack(spacing: 8) {
                // Check accessibility status
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
                let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
                
                if !trusted {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Keyboard Shortcuts Disabled")
                            .font(.headline)
                        
                        Text("Grant accessibility access to use Cmd+Shift+V shortcut")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Text("Look for 'Clipboard Manager' in\nPrivacy & Security > Accessibility")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)
                }
                
                VStack(spacing: 4) {
                    Text("Debug Info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Accessibility: \(trusted ? "✅" : "❌")")
                        .font(.caption)
                        .foregroundColor(trusted ? .green : .red)
                    
                    Text("Last Key: \(appState.lastKeyEvent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                
                if appState.isLoading {
                    ProgressView("Starting service...")
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if let error = appState.error {
                    VStack(spacing: 4) {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        
                        Button("Retry Connection (⌘R)") {
                            appState.startGoService()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .keyboardShortcut("r")
                    }
                    .padding(.horizontal)
                }
                
                HStack {
                    Circle()
                        .fill(appState.isServiceRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.isServiceRunning ? "Service Running" : "Service Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Clips count: \(appState.clips.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ClipboardHistoryView()
                    .environmentObject(appState)
                
                Divider()
                
                VStack(spacing: 2) {
                    Button("Quit Clipboard Manager (⌘Q)") {
                        print("Quit button pressed")
                        appState.cleanup()
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .keyboardShortcut("q")
                    
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Version \(version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }
}
