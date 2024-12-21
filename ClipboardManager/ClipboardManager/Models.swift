import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

// URL Error constants
private let kCFURLErrorDomain = "NSURLErrorDomain"
private let kCFURLErrorConnectionRefused = 61
private let kCFURLErrorTimedOut = -1001
private let kCFURLErrorCannotConnectToHost = -1004

class AppState: ObservableObject, ClipboardUpdateDelegate {
    private var goProcess: Process?
    private let apiClient: APIClient
    private var eventTap: CFMachPort?
    
    @Published var clips: [ClipboardItem] = []
    @Published var lastKeyEvent: String = "" // For debugging
    @Published var error: String?
    @Published var isServiceRunning = false
    @Published var isLoading = false
    
    init() {
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
        
        // Setup global shortcut
        setupGlobalShortcut()
        
        startGoService()
    }
    
    private func setupGlobalShortcut() {
        print("Setting up event tap...")
        
        // Get app bundle info for debugging
        if let bundleID = Bundle.main.bundleIdentifier {
            print("Bundle ID:", bundleID)
        }
        
        // Request accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility permissions granted:", accessibilityEnabled)
        
        // Callback for event tap
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let context = refcon else { return Unmanaged.passUnretained(event) }
            let appState = Unmanaged<AppState>.fromOpaque(context).takeUnretainedValue()
            
            if type == .keyDown {
                let flags = event.flags
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                
                // Debug logging
                print("Key event - keycode: \(keycode), flags: \(flags.rawValue)")
                DispatchQueue.main.async {
                    appState.lastKeyEvent = "Key: \(keycode), flags: \(flags.rawValue)"
                }
                
                // Check for Cmd+Shift+V (keycode 9 is 'V')
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keycode == 9 {
                    print("Shortcut detected: Cmd+Shift+V")
                    DispatchQueue.main.async {
                        PanelWindowManager.togglePanel(with: appState)
                    }
                    // Return nil to consume the event
                    return nil
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("❌ Failed to create event tap")
            self.lastKeyEvent = "Failed to create event tap"
            return
        }
        
        // Create run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Store event tap for cleanup
        eventTap = tap
        
        print("✅ Event tap setup successfully")
        self.lastKeyEvent = "Event tap initialized"
    }
    
    
    func didReceiveNewClip(_ clip: ClipboardItem) {
        DispatchQueue.main.async {
            self.clips.insert(clip, at: 0)
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
            
            try goProcess?.run()
            isServiceRunning = true
                
            // Read stdout for server status
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                if let output = String(data: data, encoding: .utf8) {
                    print("Server stdout: \(output)")
                    
                    // Look for specific server start messages
                    if output.contains("Starting HTTP server") {
                        print("Server initialization detected")
                    }
                    if output.contains("Server started successfully") {
                        print("Server started confirmation received")
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            self?.loadInitialClips()
                        }
                    }
                }
            }
            
            // Read stderr for errors
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                if let output = String(data: data, encoding: .utf8) {
                    print("Server stderr: \(output)")
                    
                    // Check for specific error patterns
                    let errorPatterns = ["error", "Error", "failed", "Failed", "permission denied"]
                    if errorPatterns.contains(where: output.contains) {
                        DispatchQueue.main.async {
                            self?.error = "Go service error: \(output)"
                            self?.isServiceRunning = false
                            self?.isLoading = false
                        }
                    }
                }
            }
            
            // Wait for the service to start
            print("Waiting for server to initialize...")
            Thread.sleep(forTimeInterval: 0.5) // Short initial wait
            
            // Check if process started
            if goProcess?.isRunning == true {
                print("Server process launched, waiting for confirmation...")
                loadInitialClips()
            } else {
                print("Server process failed to start")
                throw NSError(domain: "", code: -1, 
                            userInfo: [NSLocalizedDescriptionKey: "Server process failed to launch"])
            }
        } catch {
            print("Failed to start clipboard service: \(error)")
            self.error = error.localizedDescription
            isServiceRunning = false
            isLoading = false
        }
    }
    
    private func loadInitialClips() {
        Task {
            do {
                // Try to connect to health endpoint first
                var attempts = 0
                let maxAttempts = 10
                var connected = false
                
                while attempts < maxAttempts && !connected {
                    do {
                        // Check server health
                        let url = URL(string: "http://localhost:54321/status")!
                        let (_, response) = try await URLSession.shared.data(from: url)
                        
                        if let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200 {
                            connected = true
                            break
                        }
                    } catch {
                        attempts += 1
                        if attempts < maxAttempts {
                            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        }
                    }
                }
                
                if !connected {
                    throw NSError(domain: "", code: -1, 
                                userInfo: [NSLocalizedDescriptionKey: "Server failed to start after multiple attempts"])
                }
                
                // Load initial clips
                let initialClips = try await apiClient.getClips()
                await MainActor.run {
                    self.isLoading = false
                    self.error = nil
                    self.clips = initialClips
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.error = "Failed to connect to server: \(error.localizedDescription)"
                    self.retryConnection()
                }
            }
        }
    }
    
    private func retryConnection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            
            // Only retry if service is marked as running
            if self.isServiceRunning {
                self.loadInitialClips()
            }
        }
    }
    
    func pasteClip(at index: Int) {
        Task {
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
                    }
                }
            } catch {
                print("Unexpected error in pasteClip: \(error)")
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    func cleanup() {
        goProcess?.terminate()
        goProcess = nil
        
        isServiceRunning = false
        error = nil
        clips = []
    }
    
    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            print("Event tap disabled")
        }
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
