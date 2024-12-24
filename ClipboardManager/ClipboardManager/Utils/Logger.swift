import Foundation

class Logger {
    static var isDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DEBUG_ENABLED")
    }
    
    static func debug(_ message: String) {
        if isDebugEnabled {
            print("[DEBUG] \(message)")
        }
    }
    
    static func error(_ message: String) {
        // Always print errors
        print("[ERROR] \(message)")
    }
    
    static func warn(_ message: String) {
        // Always print warnings
        print("[WARN] \(message)")
    }
}
