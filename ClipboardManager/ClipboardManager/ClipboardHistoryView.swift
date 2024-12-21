import SwiftUI
import UserNotifications

struct ClipboardHistoryView: View {
    @State private var showToast = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @EnvironmentObject private var appState: AppState
    var isInPanel: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIndex: Int
    
    init(isInPanel: Bool = false, selectedIndex: Binding<Int> = .constant(0)) {
        self.isInPanel = isInPanel
        self._selectedIndex = selectedIndex
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Search field
            TextField("Search clips...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
                .onChange(of: searchText) { newValue in
                    // Cancel any existing search task
                    searchTask?.cancel()
                    
                    if newValue.isEmpty {
                        // Reset to normal list when search is cleared
                        Task {
                            await appState.refreshClips()
                        }
                    } else {
                        // Create new search task with debouncing
                        searchTask = Task {
                            isSearching = true
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay
                            
                            if !Task.isCancelled {
                                // First try local search
                                let searchTerm = newValue.lowercased()
                                let localResults = appState.clips.filter { clip in
                                    // Search in content
                                    if let text = clip.contentString?.lowercased(),
                                       text.contains(searchTerm) {
                                        return true
                                    }
                                    // Search in source app
                                    if let sourceApp = clip.metadata.sourceApp?.lowercased(),
                                       sourceApp.contains(searchTerm) {
                                        return true
                                    }
                                    // Search in category
                                    if let category = clip.metadata.category?.lowercased(),
                                       category.contains(searchTerm) {
                                        return true
                                    }
                                    // Search in tags
                                    if let tags = clip.metadata.tags,
                                       tags.contains(where: { $0.lowercased().contains(searchTerm) }) {
                                        return true
                                    }
                                    return false
                                }
                                
                                if !Task.isCancelled {
                                    if !localResults.isEmpty {
                                        // Use local results if found
                                        await MainActor.run {
                                            appState.clips = localResults
                                            isSearching = false
                                        }
                                    } else {
                                        // Fall back to backend search if no local results
                                        do {
                                            let results = try await appState.apiClient.searchClips(query: newValue)
                                            if !Task.isCancelled {
                                                await MainActor.run {
                                                    appState.clips = results
                                                }
                                            }
                                        } catch {
                                            print("Search error: \(error)")
                                        }
                                        
                                        await MainActor.run {
                                            isSearching = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            if appState.isDebugMode {
                if !isInPanel {
                    // Status indicator (only in menu bar)
                    HStack {
                        Circle()
                            .fill(appState.isServiceRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.isServiceRunning ? "Service Running" : "Service Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = appState.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                        .multilineTextAlignment(.center)
                }
            }
            
            Group {
                if isSearching {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 300, height: 400)
                } else if appState.isLoading {
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
                        ClipboardItemView(item: clip, isSelected: index == selectedIndex) {
                            try await appState.pasteClip(at: index)
                            if isInPanel {
                                PanelWindowManager.hidePanel()
                            }
                            // Show visual feedback that content is ready to paste
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                            if appState.isDebugMode {
                                showToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showToast = false
                                }
                            }
                        }
                        .help(appState.isDebugMode ? "Click to copy, then use Cmd+V to paste" : "")
                        .listRowBackground(index == selectedIndex ? Color.blue.opacity(0.2) : Color.clear)
                    }
                    .frame(width: 300, height: isInPanel ? 300 : 400)
                    .listStyle(.plain)
                }
            }
        }
        .padding()
        .overlay(
            Group {
                if appState.isDebugMode && showToast {
                    VStack {
                        Spacer()
                        Text("Content copied! Press Cmd+V to paste")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(10)
                            .padding(.bottom)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: showToast)
                }
            }
        )
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onPaste: () async throws -> Void
    
    @State private var isHovered = false
    @State private var isPasting = false
    @State private var error: Error?
    
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
        .background(
            Group {
                if isSelected {
                    Color.blue.opacity(0.2)
                } else if isHovered {
                    Color.gray.opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            Task {
                isPasting = true
                do {
                    try await onPaste()
                } catch {
                    print("Failed to paste clip: \(error)")
                    self.error = error
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                isPasting = false
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") {
                error = nil
            }
        } message: {
            if let error = error {
                Text(error.localizedDescription)
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
