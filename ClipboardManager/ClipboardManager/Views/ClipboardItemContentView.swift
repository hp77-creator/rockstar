import SwiftUI

struct ClipboardItemContentView: View {
    let type: String
    let content: Data
    let contentString: String?
    
    var body: some View {
        switch type {
        case "text/plain":
            if let text = contentString {
                Text(text)
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("Invalid text content")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        case "image/png", "image/jpeg", "image/gif":
            if let image = NSImage(data: content) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
            } else {
                Text("📸 Invalid image data")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        case "text/html":
            if let text = contentString {
                Text("🌐 " + text)
                    .font(.system(.body))
            } else {
                Text("🌐 Invalid HTML content")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        default:
            if let text = contentString {
                Text(text)
                    .font(.system(.body))
            } else {
                Text("Unknown content type: \(type)")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        }
    }
}
