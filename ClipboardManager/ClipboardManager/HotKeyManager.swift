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
        // Debug logging for app identification
        print("=== Accessibility Check ===")
        
        // Get bundle info
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundlePath
        let executablePath = bundle.executablePath ?? "unknown"
        let processPath = ProcessInfo.processInfo.processName
        
        print("Bundle Info:")
        print("- Bundle ID: \(bundleID)")
        print("- Bundle Path: \(bundlePath)")
        print("- Executable Path: \(executablePath)")
        print("- Process Name: \(processPath)")
        
        // Check if app is running from Xcode
        let environment = ProcessInfo.processInfo.environment
        let isRunningFromXcode = environment["XPC_SERVICE_NAME"]?.contains("com.apple.dt.Xcode") ?? false
        let isDevelopment = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        print("\nEnvironment:")
        print("- Running from Xcode: \(isRunningFromXcode)")
        print("- Running for Previews: \(isDevelopment)")
        print("- XPC Service: \(environment["XPC_SERVICE_NAME"] ?? "none")")
        
        // Check permissions using both methods
        let trusted = AXIsProcessTrusted()
        let trustedWithOptions = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        }()
        
        print("\nPermission Status:")
        print("- AXIsProcessTrusted: \(trusted)")
        print("- AXIsProcessTrustedWithOptions: \(trustedWithOptions)")
        
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
        
        print("- App is signed: \(isAppSigned)")
        
        // Use the most permissive result
        let newPermissionStatus = trusted || trustedWithOptions
        
        // Only update if status changed
        if hasAccessibilityPermissions != newPermissionStatus {
            print("\nPermission status changed: \(newPermissionStatus)")
            DispatchQueue.main.async {
                self.hasAccessibilityPermissions = newPermissionStatus
                if newPermissionStatus {
                    // Try registering again if we have appState
                    if let appState = self.appState {
                        print("Attempting to register hotkey after permission granted")
                        self.register(appState: appState)
                    }
                } else {
                    // Unregister if permissions were revoked
                    if self.isRegistered {
                        print("Unregistering hotkey after permission revoked")
                        self.unregister()
                    }
                }
            }
        }
        
        print("\nFinal Permission Status: \(hasAccessibilityPermissions)")
        print("========================")
    }
    
    func forcePermissionCheck() {
        print("Forcing permission check...")
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
        print("🔍 Starting registration with appState: \(String(describing: appState))")
        
        // Store appState even if we can't register yet
        self.appState = appState
        print("🔍 Stored appState: \(String(describing: self.appState))")
        
        // Check permissions first
        checkAccessibilityPermissions()
        
        // Don't register if already registered
        guard !isRegistered else {
            print("🔍 HotKey already registered. Current appState: \(String(describing: self.appState))")
            return
        }
        
        // Ensure we have accessibility permissions
        guard hasAccessibilityPermissions else {
            print("No accessibility permissions, requesting...")
            forcePermissionCheck()
            return
        }
        
        // Create hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CLIP".fourCharCodeValue)
        hotKeyID.id = 1
        
        print("Registering event handler...")
        
        // Register event handler
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Create event handler function
        let handler: EventHandlerProcPtr = { (_, event, _) -> OSStatus in
            print("🎯 Event handler called!")
            
            guard let event = event else {
                print("❌ No event received")
                return noErr
            }
            
            print("✅ Event received")
            
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
                print("✅ HotKey ID received: \(hotKeyID.id)")
                print("🔍 Signature: \(hotKeyID.signature)")
                
                // Use shared instance directly
                let manager = HotKeyManager.shared
                print("✅ Using shared manager instance")
                print("🔍 AppState: \(String(describing: manager.appState))")
                
                if let appState = manager.appState {
                    print("✅ Got appState")
                    print("🎯 Triggering panel toggle")
                    DispatchQueue.main.async {
                        PanelWindowManager.togglePanel(with: appState)
                    }
                } else {
                    print("❌ AppState is nil")
                }
            } else {
                print("❌ Failed to get hot key ID: \(err)")
                print("🔍 Error details: \(err)")
            }
            
            return noErr
        }
        
        // Store handler and install it
        handlerUPP = handler
        
        // Retain self before installation
        selfPtr = Unmanaged.passRetained(self).toOpaque()
        print("🔍 Self pointer created: \(String(describing: selfPtr))")
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        print("🔍 Event handler installation status: \(status)")
        
        if status == noErr {
            // Register Cmd+Shift+V
            print("🔑 Attempting to register Cmd+Shift+V hotkey")
            print("🔍 Key code: \(kVK_ANSI_V)")
            print("🔍 Modifiers: \(cmdKey | shiftKey)")
            print("🔍 Target: \(String(describing: GetApplicationEventTarget()))")
            
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                UInt32(cmdKey | shiftKey),
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(0),
                &hotKeyRef
            )
            
            print("🔍 Registration status: \(status)")
            
            if status == noErr {
                isRegistered = true
                print("HotKey registered successfully")
                print("- Key: V (keycode: \(kVK_ANSI_V))")
                print("- Modifiers: Command + Shift")
                print("- ID: \(hotKeyID.id)")
                print("- Signature: \(hotKeyID.signature)")
            } else {
                isRegistered = false
                print("Failed to register hotkey")
                print("- Status: \(status)")
                
                // Clean up
                if let ptr = selfPtr {
                    Unmanaged<HotKeyManager>.fromOpaque(ptr).release()
                    selfPtr = nil
                }
            }
        } else {
            print("Failed to install event handler: \(status)")
        }
    }
    
    func unregister() {
        print("Unregistering hotkey...")
        
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
        print("HotKey unregistered and cleaned up")
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
