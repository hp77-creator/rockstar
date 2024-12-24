import Foundation
import os.log

/// A logging utility that provides different levels of logging with build configuration awareness
class Logger {
    // MARK: - Private Properties
    
    /// The underlying logger instance
    private static let logger = Logger()
    
    /// OSLog subsystem identifier - should match your bundle identifier
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clipboard.manager"
    
    /// Different log categories for better filtering
    private static let debugLog = OSLog(subsystem: subsystem, category: "debug")
    private static let errorLog = OSLog(subsystem: subsystem, category: "error")
    private static let warnLog = OSLog(subsystem: subsystem, category: "warning")
    
    // MARK: - Public Properties
    
    /// Enable debug logs via UserDefaults (useful for user-triggered debug mode)
    static var isDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DEBUG_ENABLED")
    }
    
    // MARK: - Public Methods
    
    /// Log debug messages - only in DEBUG builds or if explicitly enabled
    static func debug(_ message: String) {
        #if DEBUG
        os_log(.debug, log: debugLog, "%{public}@", message)
        #else
        if isDebugEnabled {
            os_log(.debug, log: debugLog, "%{public}@", message)
        }
        #endif
    }
    
    /// Log error messages - only with basic info in Release
    static func error(_ message: String) {
        #if DEBUG
        os_log(.error, log: errorLog, "%{public}@", message)
        #else
        // In Release, we might want to log errors without sensitive information
        os_log(.error, log: errorLog, "An error occurred")
        #endif
    }
    
    /// Log warning messages - only with basic info in Release
    static func warn(_ message: String) {
        #if DEBUG
        os_log(.info, log: warnLog, "%{public}@", message)
        #else
        // In Release, we might want to log warnings without sensitive information
        os_log(.info, log: warnLog, "A warning occurred")
        #endif
    }
}
