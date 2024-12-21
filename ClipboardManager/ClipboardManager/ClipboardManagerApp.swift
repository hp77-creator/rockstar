import SwiftUI
import AppKit

@main
struct ClipboardManagerApp: App {
    // Keep strong reference to NSApplication and coordinator
    private let app = NSApplication.shared
    @StateObject private var appState = AppState()
    @StateObject private var hotKeyManager = HotKeyManager.shared
    @State private var showingSettings = false
    
    // Use a class-based coordinator to handle lifecycle
    private class AppCoordinator {
        private var observers: [NSObjectProtocol] = []
        
        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
        
        func setup(appState: AppState, hotKeyManager: HotKeyManager) {
            // Set up termination notification observer
            let terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak appState] _ in
                print("Application will terminate, cleaning up...")
                hotKeyManager.unregister()
                appState?.cleanup()
            }
            
            // Store observers for cleanup
            observers.append(terminationObserver)
            
            // Initial registration attempt
            hotKeyManager.register(appState: appState)
        }
    }
    
    private let coordinator = AppCoordinator()
    
    init() {
        print("ClipboardManagerApp initializing...")
        coordinator.setup(appState: appState, hotKeyManager: HotKeyManager.shared)
    }
    
    var body: some Scene {
        MenuBarExtra("Clipboard Manager", systemImage: "clipboard") {
            VStack(spacing: 8) {
                if !hotKeyManager.hasAccessibilityPermissions {
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
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Force Permission Check") {
                            hotKeyManager.forcePermissionCheck()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        
                        Text("Look for 'ClipboardManager' in\nPrivacy & Security > Accessibility")
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
                    
                    Text("Accessibility: \(hotKeyManager.hasAccessibilityPermissions ? "✅" : "❌")")
                        .font(.caption)
                        .foregroundColor(hotKeyManager.hasAccessibilityPermissions ? .green : .red)
                    
                    Text("HotKey: \(hotKeyManager.isRegistered ? "✅" : "❌")")
                        .font(.caption)
                        .foregroundColor(hotKeyManager.isRegistered ? .green : .red)
                    
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                
                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    SettingsWindowController.showSettings()
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                
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
