import SwiftUI
import AppKit

class SettingsHostingController: NSHostingController<SettingsView> {
    override func loadView() {
        view = NSView()
        view.setFrameSize(NSSize(width: 350, height: 150))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let window = view.window {
            window.title = "Settings"
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable]
            window.center()
            window.isMovableByWindowBackground = true
            window.backgroundColor = .windowBackgroundColor
        }
    }
}
