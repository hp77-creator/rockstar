import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

// Constants
private let kCFURLErrorDomain = "NSURLErrorDomain"
public enum UserDefaultsKeys {
    static let maxClipsShown = "maxClipsShown"
    static let obsidianEnabled = "obsidianEnabled"
    static let obsidianVaultPath = "obsidianVaultPath"
    static let obsidianVaultBookmark = "obsidianVaultBookmark"
    static let obsidianSyncInterval = "obsidianSyncInterval" // in minutes
    static let playSoundOnCopy = "playSoundOnCopy"
    static let selectedSound = "selectedSound"
}

private let kCFURLErrorConnectionRefused = 61
private let kCFURLErrorTimedOut = -1001
private let kCFURLErrorCannotConnectToHost = -1004

class AppState: ObservableObject, ClipboardUpdateDelegate {
    private var goProcess: Process?
    private var obsidianVaultURL: URL?
    let apiClient: APIClient // Made public for access from views
    @Published var clips: [ClipboardItem] = []
    @Published var error: String?
    @Published var isServiceRunning = false
    @Published var isLoading = false
    
    // Memory management
    private let maxCachedClips = 100
    private var isViewActive = false
    
    #if DEBUG
    @Published var isDebugMode = true
    #else
    @Published var isDebugMode = false
    #endif
    
    init() {
        #if DEBUG
        print("Running in DEBUG configuration")
        #else
        print("Running in RELEASE configuration")
        #endif
        
        // Initialize properties before using them
        clips = []
        error = nil
        isServiceRunning = false
        isLoading = false
        
        // Create temporary APIClient
        let client = APIClient()
        self.apiClient = client
        
        // Set delegate after initialization
        client.delegate = self
        
        // Listen for restart notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRestartService),
            name: NSNotification.Name("RestartGoService"),
            object: nil
        )
        
        startGoService()
    }
    
    @objc private func handleRestartService() {
        print("Restarting Go service due to Obsidian settings change")
        print("- Enabled: \(UserDefaults.standard.bool(forKey: UserDefaultsKeys.obsidianEnabled))")
        print("- Vault Path: \(UserDefaults.standard.string(forKey: UserDefaultsKeys.obsidianVaultPath) ?? "not set")")
        print("- Sync Interval: \(UserDefaults.standard.integer(forKey: UserDefaultsKeys.obsidianSyncInterval)) minutes")
        
        // Delay the restart to allow WebSocket to close gracefully
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // Clean up existing connections
            self.apiClient.disconnect()
            
            // Wait a bit for connections to close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startGoService()
            }
        }
    }
    
    
    func didReceiveNewClip(_ clip: ClipboardItem) {
        print("New clip received: \(clip.id)")
        DispatchQueue.main.async {
            // Insert new clip at the beginning
            self.clips.insert(clip, at: 0)
            
            // Trim cache if needed
            if self.clips.count > self.maxCachedClips {
                self.clips = Array(self.clips.prefix(self.maxCachedClips))
            }
            
            // Play sound when new clip is received
            print("Playing sound for new clip")
            SoundManager.shared.playCopySound()
        }
    }
    
    // Call this when the view appears
    func viewActivated() {
        isViewActive = true
    }
    
    // Call this when the view disappears
    func viewDeactivated() {
        isViewActive = false
        // Trim cache more aggressively when view is not active
        if clips.count > maxCachedClips / 2 {
            clips = Array(clips.prefix(maxCachedClips / 2))
        }
    }
    
    func startGoService() {
        isLoading = true
        error = nil // Clear previous errors
        
        // Clean up any existing process
        goProcess?.terminate()
        
        goProcess = Process()
        
        do {
            guard let path = Bundle.main.path(forResource: "clipboard-manager", ofType: "") else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find clipboard-manager executable in Resources"])
            }
            
            guard let resourcePath = Bundle.main.resourcePath else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get resource path"])
            }
            
            // Verify executable permissions
            let fileManager = FileManager.default
            var attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: path)
                let permissions = attributes[.posixPermissions] as? NSNumber
                if permissions?.int16Value != 0o755 {
                    print("Fixing executable permissions")
                    try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: path)
                }
            } catch {
                print("Failed to verify/set executable permissions: \(error)")
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to set executable permissions"])
            }
            
            goProcess?.executableURL = URL(fileURLWithPath: path)
            goProcess?.arguments = [] // Remove verbose flag to reduce logging
            
            goProcess?.currentDirectoryPath = resourcePath
            
            // Set up paths and environment
            let dbPath = (resourcePath as NSString).appendingPathComponent("clipboard.db")
            let fsPath = (resourcePath as NSString).appendingPathComponent("files")
            let dbDir = (dbPath as NSString).deletingLastPathComponent
            
            // Create necessary directories
            try FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(atPath: fsPath, withIntermediateDirectories: true, attributes: nil)
            
            // Set up environment variables
            var env = ProcessInfo.processInfo.environment
            
            // Essential environment variables
            env["HOME"] = NSHomeDirectory()
            env["TMPDIR"] = NSTemporaryDirectory()
            env["USER"] = NSUserName()
            
            // App-specific variables
            env["CLIPBOARD_DB_PATH"] = dbPath
            env["CLIPBOARD_FS_PATH"] = fsPath
            env["CLIPBOARD_API_PORT"] = "54321"
            
            // Obsidian settings
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.obsidianEnabled) {
                // Resolve security-scoped bookmark
                if let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKeys.obsidianVaultBookmark) {
                    var isStale = false
                    do {
                        let url = try URL(resolvingBookmarkData: bookmarkData,
                                        options: .withSecurityScope,
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale)
                        
                        if isStale {
                            print("Warning: Bookmark is stale")
                        }
                        
                        // Start accessing security-scoped resource
                        if url.startAccessingSecurityScopedResource() {
                            obsidianVaultURL = url // Store URL for cleanup
                            env["OBSIDIAN_ENABLED"] = "true"
                            env["OBSIDIAN_VAULT_PATH"] = url.path
                            env["OBSIDIAN_SYNC_INTERVAL"] = String(UserDefaults.standard.integer(forKey: UserDefaultsKeys.obsidianSyncInterval))
                        } else {
                            print("Failed to access security-scoped resource")
                        }
                    } catch {
                        print("Failed to resolve bookmark: \(error)")
                    }
                }
            }
            
            #if DEBUG
            env["CLIPBOARD_DEBUG"] = "true"
            #endif
            
            // Ensure PATH includes common locations
            let defaultPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = [env["PATH"] ?? "", defaultPath].joined(separator: ":")
            
            goProcess?.environment = env
            
            // Set up pipes for stdout and stderr
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            goProcess?.standardOutput = stdoutPipe
            goProcess?.standardError = stderrPipe
            
            print("Starting Go server process:")
            print("- Executable: \(path)")
            print("- Working Directory: \(resourcePath)")
            print("- Database Path: \(dbPath)")
            print("- Files Path: \(fsPath)")
            print("- Home Directory: \(env["HOME"] ?? "not set")")
            print("- User: \(env["USER"] ?? "not set")")
            print("- PATH: \(env["PATH"] ?? "not set")")
            
            // Set up logging handlers
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let output = String(data: data, encoding: .utf8) {
                    print("Server stdout: \(output)")
                }
            }
            
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let output = String(data: data, encoding: .utf8) {
                    print("Server stderr: \(output)")
                }
            }
            
            // Start the process
            try goProcess?.run()
            
            // Start health check and initialization in background
            Task {
                // Give the server a moment to start
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                
                // Start checking server health
                var attempts = 0
                let maxAttempts = 20 // Increased attempts with shorter intervals
                
                while attempts < maxAttempts {
                    do {
                        let url = URL(string: "http://localhost:54321/status")!
                        let (_, response) = try await URLSession.shared.data(from: url)
                        
                        if let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200 {
                            print("Server health check passed")
                            
                            // Server is healthy, load initial clips
                            await MainActor.run {
                                self.isServiceRunning = true
                                self.error = nil
                                self.loadInitialClips()
                            }
                            return
                        }
                    } catch {
                        print("Health check attempt \(attempts + 1) failed: \(error)")
                    }
                    
                    attempts += 1
                    if attempts < maxAttempts {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms between attempts
                    }
                }
                
                print("Server health checks exhausted")
                // Don't update service status since clips might still work
            }
        } catch {
            print("Failed to start clipboard service: \(error)")
            self.error = error.localizedDescription
            isServiceRunning = false
            isLoading = false
        }
    }
    
    func refreshClips() async {
        do {
            let clips = try await apiClient.getClips(limit: maxCachedClips)
            await MainActor.run {
                self.isLoading = false
                self.error = nil
                self.clips = clips
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to refresh clips: \(error.localizedDescription)"
            }
        }
    }

    private func loadInitialClips() {
        Task {
            do {
                let initialClips = try await apiClient.getClips()
                await MainActor.run {
                    self.isLoading = false
                    self.error = nil
                    self.clips = initialClips
                    self.isServiceRunning = true  // Service is running if we got clips
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Failed to load initial clips: \(error)")
                    // Don't mark service as stopped, it might still be starting
                    self.retryConnection()
                }
            }
        }
    }
    
    private func retryConnection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            
            // Only retry if service is marked as running and not restarting
            if self.isServiceRunning {
                print("Retrying connection...")
                self.loadInitialClips()
            } else {
                print("Service not running, skipping retry")
            }
        }
    }
    
    @discardableResult
    func pasteClip(at index: Int) async throws {
        do {
            try await apiClient.pasteClip(at: index)
            await MainActor.run {
                self.error = nil  // Clear any previous errors on success
            }
        } catch {
            let nsError = error as NSError
            print("Network error in pasteClip: \(nsError.code) - \(nsError.localizedDescription)")
            await MainActor.run {
                if nsError.domain == kCFURLErrorDomain {
                    switch nsError.code {
                    case kCFURLErrorConnectionRefused:
                        self.error = "Server connection lost"
                        self.retryConnection()
                    case kCFURLErrorTimedOut:
                        self.error = "Paste request timed out"
                    case kCFURLErrorCannotConnectToHost:
                        self.error = "Cannot connect to server"
                        self.retryConnection()
                    default:
                        self.error = "Network error: \(error.localizedDescription)"
                    }
                } else {
                    self.error = error.localizedDescription
                }
            }
            throw error
        } catch let error as APIError {
            print("API error in pasteClip: \(error)")
            await MainActor.run {
                switch error {
                case .invalidURL:
                    self.error = "Invalid server URL"
                case .invalidResponse:
                    self.error = "Invalid server response"
                case .networkError(let underlying):
                    self.error = "Network error: \(underlying.localizedDescription)"
                    self.retryConnection()
                case .decodingError(let decodingError):
                    self.error = "Data error: \(decodingError.localizedDescription)"
                case .sessionInvalidated:
                    print("Session invalidated, restarting service")
                    self.startGoService()
                }
            }
            throw error
        } catch {
            print("Unexpected error in pasteClip: \(error)")
            await MainActor.run {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    func cleanup() {
        // Stop accessing security-scoped resource
        if let url = obsidianVaultURL {
            url.stopAccessingSecurityScopedResource()
            obsidianVaultURL = nil
        }
        
        // Clean up connections before terminating
        apiClient.disconnect()
        
        // Wait a bit for connections to close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            self.goProcess?.terminate()
            self.goProcess = nil
            
            self.isServiceRunning = false
            self.error = nil
            self.clips = []
        }
    }
    
    deinit {
        cleanup()
    }
}

struct ClipboardItem: Codable, Identifiable {
    let id: String
    let content: Data
    let type: String
    let createdAt: Date
    let metadata: ClipMetadata
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case content = "Content"
        case type = "Type"
        case createdAt = "CreatedAt"
        case metadata = "Metadata"
    }
    
    // Computed property to get numeric ID if needed
    var numericId: Int? {
        return Int(id)
    }
    
    // Computed property to get content as string if possible
    var contentString: String? {
        return String(data: content, encoding: .utf8)
    }
}

struct ClipMetadata: Codable {
    let sourceApp: String?
    let category: String?
    let tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case sourceApp = "SourceApp"
        case category = "Category"
        case tags = "Tags"
    }
}

struct WebSocketMessage: Codable {
    let type: String
    let payload: ClipboardItem?
}
