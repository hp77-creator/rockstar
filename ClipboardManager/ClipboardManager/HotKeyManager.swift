import SwiftUI
import Carbon.HIToolbox

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    fileprivate weak var appState: AppState?
    private var selfPtr: UnsafeMutableRawPointer?
    private var handlerUPP: EventHandlerProcPtr?
    
    // Track registration status
    private(set) var isRegistered: Bool = false
    
    private init() {}
    
    func register(appState: AppState) {
        // Don't register if already registered
        guard !isRegistered else { return }
        
        self.appState = appState
        
        // Create hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CLIP".fourCharCodeValue)
        hotKeyID.id = 1
        
        print("Registering event handler...")
        
        // Register event handler
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Install handler
        selfPtr = Unmanaged.passRetained(self).toOpaque()
        
        // Create event handler function
        let handler: EventHandlerProcPtr = { [weak self] (_, event, userData) -> OSStatus in
            guard let event = event else {
                print("No event received")
                return noErr
            }
            
            guard let context = userData else {
                print("No user data received")
                return noErr
            }
            
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
                print("HotKey ID received: \(hotKeyID.id)")
                if let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue() as? HotKeyManager,
                   let appState = manager.appState {
                    print("Triggering panel toggle")
                    DispatchQueue.main.async {
                        PanelWindowManager.togglePanel(with: appState)
                    }
                } else {
                    print("Failed to get manager or appState")
                }
            } else {
                print("Failed to get hot key ID: \(err)")
            }
            
            return noErr
        }
        
        // Store handler and install it
        handlerUPP = handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        
        if status == noErr {
            // Register Cmd+Shift+V
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                UInt32(cmdKey | shiftKey),
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(0),
                &hotKeyRef
            )
            
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
