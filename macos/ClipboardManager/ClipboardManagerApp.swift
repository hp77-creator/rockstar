import SwiftUI

@main
struct ClipboardManagerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Clipboard Manager", systemImage: "clipboard") {
            ClipboardHistoryView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    private var goProcess: Process?
    private let apiClient = APIClient()
    @Published var clips: [ClipboardItem] = []
    @Published var error: String?
    
    init() {
        startGoService()
        startPollingClips()
    }
    
    private func startGoService() {
        goProcess = Process()
        if let path = Bundle.main.path(forResource: "clipboard-manager", ofType: "") {
            goProcess?.executableURL = URL(fileURLWithPath: path)
            goProcess?.arguments = ["--verbose"]
            
            do {
                try goProcess?.run()
                // Wait a bit for the service to start
                Thread.sleep(forTimeInterval: 1.0)
            } catch {
                self.error = "Failed to start clipboard service: \(error.localizedDescription)"
            }
        } else {
            self.error = "Could not find clipboard-manager executable"
        }
    }
    
    private func startPollingClips() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchClips()
        }
    }
    
    private func fetchClips() {
        Task {
            do {
                let newClips = try await apiClient.getClips()
                await MainActor.run {
                    self.clips = newClips
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    func pasteClip(at index: Int) {
        Task {
            do {
                try await apiClient.pasteClip(at: index)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    deinit {
        goProcess?.terminate()
    }
}
