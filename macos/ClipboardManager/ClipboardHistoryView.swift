import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack {
            if let error = appState.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            List(appState.clips) { clip in
                ClipboardItemView(item: clip)
                    .onTapGesture {
                        if let index = appState.clips.firstIndex(where: { $0.id == clip.id }) {
                            appState.pasteClip(at: index)
                        }
                    }
            }
            .frame(width: 300, height: 400)
        }
        .padding()
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.content)
                .lineLimit(2)
                .font(.system(.body, design: .monospaced))
            
            HStack {
                if let sourceApp = item.metadata.sourceApp {
                    Text(sourceApp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
