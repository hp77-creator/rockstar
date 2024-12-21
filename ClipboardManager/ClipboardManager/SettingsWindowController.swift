import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    convenience init(rootView: SettingsView) {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 150),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.level = .floating
        self.init(window: window)
        window.delegate = self
    }
    
    private static var shared: SettingsWindowController?
    
    static func showSettings() {
        if shared == nil {
            shared = SettingsWindowController(rootView: SettingsView())
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Keep the controller in memory
        Self.shared = nil
    }
}
