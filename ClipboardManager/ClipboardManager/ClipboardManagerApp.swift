import SwiftUI
import AppKit

// Coordinator to handle app lifecycle and state
class AppCoordinator: ObservableObject {
    private var observers: [NSObjectProtocol] = []
    private var hotKeyManager: HotKeyManager?
    private var appState: AppState?
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func setup(appState: AppState, hotKeyManager: HotKeyManager) {
        print("🔍 AppCoordinator setup starting")
        self.hotKeyManager = hotKeyManager
        self.appState = appState
        
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
        
        // Register hotkey
        hotKeyManager.register(appState: appState)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AppCoordinator?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🔍 App launching")
        
        // Set as regular app first to ensure proper event handling
        NSApp.setActivationPolicy(.regular)
        
        // Enable background operation
        NSApp.activate(ignoringOtherApps: true)
        
        // Wait a bit to ensure event handling is set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Then switch to accessory mode (menu bar app without dock icon)
            NSApp.setActivationPolicy(.accessory)
            
            print("🔍 App activation policy set to accessory")
            print("🔍 App activation state: \(NSApp.isActive)")
            print("🔍 App responds to events: \(NSApp.isRunning)")
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        print("🔍 App did become active")
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        print("🔍 App did resign active")
    }
}

@main
struct ClipboardManagerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var hotKeyManager = HotKeyManager.shared
    @StateObject private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showingSettings = false
    
    init() {
        print("ClipboardManagerApp initializing...")
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
                            self.hotKeyManager.forcePermissionCheck()
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
                
                if appState.isDebugMode {
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
                }
                
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
                            self.appState.startGoService()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .keyboardShortcut("r")
                    }
                    .padding(.horizontal)
                }
                
                if appState.isDebugMode {
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
                }
                
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
                        self.appState.cleanup()
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
            .task {
                // Setup coordinator when view appears
                coordinator.setup(appState: appState, hotKeyManager: hotKeyManager)
                appDelegate.coordinator = coordinator
            }
        }
        .menuBarExtraStyle(.window)
    }
}
