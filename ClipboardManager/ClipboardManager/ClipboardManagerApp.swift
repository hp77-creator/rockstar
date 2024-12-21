import SwiftUI
import AppKit

@main
struct ClipboardManagerApp: App {
    // Keep strong reference to NSApplication and coordinator
    private let app = NSApplication.shared
    @StateObject private var appState = AppState()
    
    // Use a class-based coordinator to handle lifecycle
    private class AppCoordinator {
        let hotKeyManager = HotKeyManager.shared
        private var observers: [NSObjectProtocol] = []
        private var accessibilityCheckTimer: Timer?
        
        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            accessibilityCheckTimer?.invalidate()
        }
        
        func setup(appState: AppState) {
            // Initial accessibility check
            checkAndHandleAccessibility(appState: appState)
            
            // Set up periodic accessibility check
            accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkAndHandleAccessibility(appState: appState)
            }
            
            // Set up termination notification observer
            let terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak appState] _ in
                print("Application will terminate, cleaning up...")
                self?.hotKeyManager.unregister()
                appState?.cleanup()
            }
            
            // Store observers for cleanup
            observers.append(terminationObserver)
        }
        
        private func checkAndHandleAccessibility(appState: AppState) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if trusted {
                // Only register if not already registered
                if !hotKeyManager.isRegistered {
                    print("Registering hotkey after accessibility granted")
                    hotKeyManager.register(appState: appState)
                }
            } else {
                // Unregister if permissions were revoked
                if hotKeyManager.isRegistered {
                    print("Unregistering hotkey after accessibility revoked")
                    hotKeyManager.unregister()
                }
            }
        }
    }
    
    private let coordinator = AppCoordinator()
    
    init() {
        print("ClipboardManagerApp initializing...")
        coordinator.setup(appState: appState)
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
