import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    fileprivate var appState: AppState?
    private var selfPtr: UnsafeMutableRawPointer?
    private var handlerUPP: EventHandlerProcPtr?
    private var permissionCheckTimer: Timer?
    
    // Track registration status
    @Published private(set) var isRegistered: Bool = false
    @Published private(set) var hasAccessibilityPermissions: Bool = false
    
    private init() {
        checkAccessibilityPermissions()
        startPermissionCheckTimer()
    }
    
    private func startPermissionCheckTimer() {
        // Check permissions every second
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermissions()
        }
    }
    
    private func checkAccessibilityPermissions() {
        #if DEBUG
        // Debug logging for app identification
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundlePath
        let executablePath = bundle.executablePath ?? "unknown"
        let processPath = ProcessInfo.processInfo.processName
        
        let environment = ProcessInfo.processInfo.environment
        let isRunningFromXcode = environment["XPC_SERVICE_NAME"]?.contains("com.apple.dt.Xcode") ?? false
        let isDevelopment = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        Logger.debug("""
        === Accessibility Check ===
        Bundle Info:
        - Bundle ID: \(bundleID)
        - Bundle Path: \(bundlePath)
        - Executable Path: \(executablePath)
        - Process Name: \(processPath)
        
        Environment:
        - Running from Xcode: \(isRunningFromXcode)
        - Running for Previews: \(isDevelopment)
        - XPC Service: \(environment["XPC_SERVICE_NAME"] ?? "none")
        """)
        #endif
        
        // Check permissions using both methods
        let trusted = AXIsProcessTrusted()
        let trustedWithOptions = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        }()
        
        #if DEBUG
        Logger.debug("""
        Permission Status:
        - AXIsProcessTrusted: \(trusted)
        - AXIsProcessTrustedWithOptions: \(trustedWithOptions)
        """)
        #endif
        
        // Check if the app is properly signed
        let isAppSigned = {
            let secCode = UnsafeMutablePointer<SecCode?>.allocate(capacity: 1)
            defer { secCode.deallocate() }
            
            var status = SecCodeCopySelf([], secCode)
            if status == errSecSuccess {
                var requirement: SecRequirement?
                status = SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement)
                if status == errSecSuccess, let req = requirement {
                    status = SecCodeCheckValidity(secCode.pointee!, [], req)
                    return status == errSecSuccess
                }
            }
            return false
        }()
        
        #if DEBUG
        Logger.debug("App is signed: \(isAppSigned)")
        #endif
        
        // Use the most permissive result
        let newPermissionStatus = trusted || trustedWithOptions
        
        // Only update if status changed
        if hasAccessibilityPermissions != newPermissionStatus {
            Logger.debug("Permission status changed: \(newPermissionStatus)")
            DispatchQueue.main.async {
                self.hasAccessibilityPermissions = newPermissionStatus
                if newPermissionStatus {
                    // Try registering again if we have appState
                    if let appState = self.appState {
                        Logger.debug("Attempting to register hotkey after permission granted")
                        self.register(appState: appState)
                    }
                } else {
                    // Unregister if permissions were revoked
                    if self.isRegistered {
                        Logger.debug("Unregistering hotkey after permission revoked")
                        self.unregister()
                    }
                }
            }
        }
        
        #if DEBUG
        Logger.debug("""
        Final Permission Status: \(hasAccessibilityPermissions)
        ========================
        """)
        #endif
    }
    
    func forcePermissionCheck() {
        Logger.debug("Forcing permission check...")
        // First unregister any existing hotkey
        unregister()
        
        // Reset permission status
        hasAccessibilityPermissions = false
        
        // Request permissions with prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Wait a bit longer before checking again to allow the user to grant permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermissions()
        }
    }
    
    func register(appState: AppState) {
        #if DEBUG
        Logger.debug("Starting registration with appState: \(String(describing: appState))")
        #endif
        
        // Store appState even if we can't register yet
        self.appState = appState
        
        #if DEBUG
        Logger.debug("Stored appState: \(String(describing: self.appState))")
        #endif
        
        // Check permissions first
        checkAccessibilityPermissions()
        
        // Don't register if already registered
        guard !isRegistered else {
            Logger.debug("HotKey already registered. Current appState: \(String(describing: self.appState))")
            return
        }
        
        // Ensure we have accessibility permissions
        guard hasAccessibilityPermissions else {
            Logger.debug("No accessibility permissions, requesting...")
            forcePermissionCheck()
            return
        }
        
        // Create hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CLIP".fourCharCodeValue)
        hotKeyID.id = 1
        
        Logger.debug("Registering event handler...")
        
        // Register event handler
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Create event handler function
        let handler: EventHandlerProcPtr = { (_, event, _) -> OSStatus in
            Logger.debug("Event handler called!")
            
            guard let event = event else {
                Logger.debug("No event received")
                return noErr
            }
            
            Logger.debug("Event received")
            
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if err == noErr {
                // Use shared instance directly
                let manager = HotKeyManager.shared
                
                #if DEBUG
                Logger.debug("""
                HotKey ID received: \(hotKeyID.id)
                Signature: \(hotKeyID.signature)
                Using shared manager instance
                AppState: \(String(describing: manager.appState))
                """)
                #endif
                
                if let appState = manager.appState {
                    #if DEBUG
                    Logger.debug("Got appState, triggering panel toggle")
                    #endif
                    DispatchQueue.main.async {
                        SingleClipPanelManager.togglePanel(with: appState)
                    }
                } else {
                    Logger.debug("AppState is nil")
                }
            } else {
                Logger.error("Failed to get hot key ID: \(err)")
            }
            
            return noErr
        }
        
        // Store handler and install it
        handlerUPP = handler
        
        // Retain self before installation
        selfPtr = Unmanaged.passRetained(self).toOpaque()
        #if DEBUG
        Logger.debug("Self pointer created: \(String(describing: selfPtr))")
        #endif
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        #if DEBUG
        Logger.debug("Event handler installation status: \(status)")
        #endif
        
        if status == noErr {
            // Register Cmd+Shift+V
            #if DEBUG
            Logger.debug("""
            Attempting to register Cmd+Shift+V hotkey
            Key code: \(kVK_ANSI_V)
            Modifiers: \(cmdKey | shiftKey)
            Target: \(String(describing: GetApplicationEventTarget()))
            """)
            #endif
            
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                UInt32(cmdKey | shiftKey),
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(0),
                &hotKeyRef
            )
            
            #if DEBUG
            Logger.debug("Registration status: \(status)")
            #endif
            
            if status == noErr {
                isRegistered = true
                #if DEBUG
                Logger.debug("""
                HotKey registered successfully
                - Key: V (keycode: \(kVK_ANSI_V))
                - Modifiers: Command + Shift
                - ID: \(hotKeyID.id)
                - Signature: \(hotKeyID.signature)
                """)
                #endif
            } else {
                isRegistered = false
                Logger.error("""
                Failed to register hotkey
                - Status: \(status)
                """)
                
                // Clean up
                if let ptr = selfPtr {
                    Unmanaged<HotKeyManager>.fromOpaque(ptr).release()
                    selfPtr = nil
                }
            }
        } else {
            Logger.error("Failed to install event handler: \(status)")
        }
    }
    
    func unregister() {
        Logger.debug("Unregistering hotkey...")
        
        // Clean up event handler
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        
        // Clean up hot key
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        
        // Release the retained self pointer
        if let ptr = selfPtr {
            Unmanaged<HotKeyManager>.fromOpaque(ptr).release()
            selfPtr = nil
        }
        
        isRegistered = false
        Logger.debug("HotKey unregistered and cleaned up")
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
        unregister()
    }
}

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        if let data = self.data(using: .macOSRoman) {
            data.prefix(4).forEach { result = (result << 8) + FourCharCode($0) }
        }
        return result
    }
}
