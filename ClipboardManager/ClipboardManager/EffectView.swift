import SwiftUI
import AppKit

struct EffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    
    init(_ material: NSVisualEffectView.Material) {
        self.material = material
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
