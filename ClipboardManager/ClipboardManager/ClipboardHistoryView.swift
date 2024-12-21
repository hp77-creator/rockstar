import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            // Status indicator
            HStack {
                Circle()
                    .fill(appState.isServiceRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isServiceRunning ? "Service Running" : "Service Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let error = appState.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
                    .multilineTextAlignment(.center)
            }
            
            Group {
                if appState.isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text("Loading clips...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 300, height: 400)
                } else if appState.clips.isEmpty {
                    VStack(spacing: 8) {
                        if appState.isServiceRunning {
                            Image(systemName: "clipboard")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No clips available")
                                .foregroundColor(.secondary)
                            Text("Copy something to get started")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text("Waiting for service to start...")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 300, height: 400)
                } else {
                    List(Array(appState.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipboardItemView(item: clip) {
                            appState.pasteClip(at: index)
                        }
                    }
                    .frame(width: 300, height: 400)
                }
            }
        }
        .padding()
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    let onPaste: () -> Void
    
    @State private var isHovered = false
    @State private var isPasting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            contentView
                .lineLimit(2)
            
            HStack {
                if let sourceApp = item.metadata.sourceApp {
                    HStack(spacing: 4) {
                        Image(systemName: "app.circle.fill")
                            .foregroundColor(.secondary)
                        Text(sourceApp)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isPasting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(item.createdAt, style: .relative)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            Task {
                isPasting = true
                onPaste()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                isPasting = false
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case "text/plain":
            if let text = item.contentString {
                Text(text)
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("Invalid text content")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        case "image/png", "image/jpeg", "image/gif":
            if let image = NSImage(data: item.content) {
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
            if let text = item.contentString {
                Text("🌐 " + text)
                    .font(.system(.body))
            } else {
                Text("🌐 Invalid HTML content")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        default:
            if let text = item.contentString {
                Text(text)
                    .font(.system(.body))
            } else {
                Text("Unknown content type: \(item.type)")
                    .font(.system(.body))
                    .foregroundColor(.red)
            }
        }
    }
}
