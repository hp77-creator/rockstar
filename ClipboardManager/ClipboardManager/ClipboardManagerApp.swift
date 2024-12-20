import SwiftUI

@main
struct ClipboardManagerApp: App {
    @StateObject private var appState = AppState()
    
    init() {
        print("ClipboardManagerApp initializing...")
        
        // Set up termination notification observer
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [appState] _ in
            print("Application will terminate, cleaning up...")
            appState.cleanup()
        }
    }
    
    var body: some Scene {
        MenuBarExtra("Clipboard Manager", systemImage: "clipboard") {
            VStack(spacing: 8) {
                Text("Debug Info")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
