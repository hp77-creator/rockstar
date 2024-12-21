import SwiftUI
import AppKit

class DeleteConfirmationWindowController: NSWindowController, NSWindowDelegate {
    private var onDelete: () -> Void = {}
    private var eventMonitor: Any?
    
    convenience init(clipToDelete: ClipboardItem, onDelete: @escaping () -> Void) {
        self.init(window: nil)
        self.onDelete = onDelete
        
        let rootView = DeleteConfirmationView(
            clipToDelete: clipToDelete,
            onDelete: { [weak self] in
                onDelete()
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )
        
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = controller
        window.title = "Delete Confirmation"
        window.titlebarAppearsTransparent = true
        window.center()
        window.setFrameAutosaveName("DeleteConfirmationWindow")
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.hasShadow = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        
        // Handle escape key
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.close()
                return nil
            }
            return event
        }
        self.window = window
        window.delegate = self
    }
    
    private static var shared: DeleteConfirmationWindowController?
    
    static func showDeleteConfirmation(for clip: ClipboardItem, onDelete: @escaping () -> Void) {
        // Always create a new instance to ensure fresh state
        shared = DeleteConfirmationWindowController(clipToDelete: clip, onDelete: onDelete)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        
        // Center on active screen
        if let window = shared?.window, let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let newOrigin = NSPoint(
                x: screenRect.midX - window.frame.width / 2,
                y: screenRect.midY - window.frame.height / 2
            )
            window.setFrameOrigin(newOrigin)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        Self.shared = nil
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
}
