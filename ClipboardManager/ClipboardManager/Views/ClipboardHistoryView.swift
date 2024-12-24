import SwiftUI
import UserNotifications
import AppKit

struct ClipboardHistoryView: View {
    @State private var showToast = false
    @State private var searchText = ""
    @State private var searchState = SearchState.initial()
    @State private var hasInitialized = false
    @State private var isLoadingMore = false
    @State private var showDeleteConfirmation = false
    @State private var clipToDelete: ClipboardItem?
    @State private var showClearConfirmation = false
    @EnvironmentObject private var appState: AppState
    var isInPanel: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIndex: Int
    
    private let pageSize = 20
    private let searchManager = SearchManager()
    
    init(isInPanel: Bool = false, selectedIndex: Binding<Int> = .constant(0)) {
        self.isInPanel = isInPanel
        self._selectedIndex = selectedIndex
    }
    
    private func loadPage(_ page: Int) async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        do {
            let newClips = try await appState.apiClient.getClips(offset: page * pageSize, limit: pageSize)
            await MainActor.run {
                if page == 0 {
                    searchState.clips = newClips
                } else {
                    searchState.clips.append(contentsOf: newClips)
                }
                searchState.hasMoreContent = newClips.count == pageSize
                searchState.currentPage = page
                isLoadingMore = false
            }
        } catch {
            print("Error loading page \(page): \(error)")
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    private func loadMoreContentIfNeeded(currentItem item: ClipboardItem) {
        let thresholdIndex = searchState.clips.index(searchState.clips.endIndex, offsetBy: -5)
        if let itemIndex = searchState.clips.firstIndex(where: { $0.id == item.id }),
           itemIndex == thresholdIndex {
            Task {
                await loadPage(searchState.currentPage + 1)
            }
        }
    }
    
    private func handleSearch(_ query: String) async {
        guard hasInitialized else {
            hasInitialized = true
            return
        }
        
        searchState.isSearching = true
        let result = await searchManager.search(
            query: query,
            in: appState.clips,
            apiClient: appState.apiClient
        )
        
        await MainActor.run {
            result.updateState(&searchState)
            if case .resetToInitial = result {
                Task {
                    await loadPage(0)
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Search bar
            SearchBar(
                searchText: $searchText,
                onClearAll: { showClearConfirmation = true },
                isEnabled: !searchState.clips.isEmpty
            )
            .onChange(of: searchText) { newValue in
                Task {
                    await handleSearch(newValue)
                }
            }
            
            // Debug status
            if appState.isDebugMode && !isInPanel {
                StatusView(
                    isServiceRunning: appState.isServiceRunning,
                    error: appState.error
                )
            }
            
            // Main content
            Group {
                if searchState.isSearching {
                    LoadingView(message: "Searching...")
                } else if appState.isLoading && searchState.clips.isEmpty {
                    LoadingView(message: "Loading clips...")
                } else if searchState.clips.isEmpty {
                    EmptyStateView(isServiceRunning: appState.isServiceRunning)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(searchState.clips.enumerated()), id: \.offset) { index, clip in
                                ClipboardItemView(
                                    item: clip,
                                    isSelected: index == searchState.selectedIndex,
                                    onDelete: {
                                        withAnimation {
                                            clipToDelete = clip
                                            showDeleteConfirmation = true
                                        }
                                    }
                                ) {
                                    try await appState.pasteClip(at: index)
                                    if isInPanel {
                                        PanelWindowManager.hidePanel()
                                    }
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                    // Always show toast to inform user they need to press Cmd+V
                                    showToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showToast = false
                                    }
                                }
                                .help("Click to copy, then use Cmd+V to paste")
                                .background(index == searchState.selectedIndex ? Color.blue.opacity(0.2) : Color.clear)
                                .onAppear {
                                    loadMoreContentIfNeeded(currentItem: clip)
                                }
                            }
                            
                            if isLoadingMore && searchState.hasMoreContent {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                    .frame(height: 40)
                            }
                        }
                    }
                    .frame(width: 300, height: isInPanel ? 300 : 400)
                }
            }
        }
        .padding()
        .confirmationDialog(
            "Delete Clip",
            isPresented: $showDeleteConfirmation,
            presenting: clipToDelete
        ) { clip in
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await appState.apiClient.deleteClip(id: clip.id)
                        await loadPage(0)
                        await MainActor.run {
                            withAnimation {
                                showDeleteConfirmation = false
                                clipToDelete = nil
                            }
                        }
                    } catch {
                        print("Error deleting clip: \(error)")
                        await MainActor.run {
                            withAnimation {
                                showDeleteConfirmation = false
                                clipToDelete = nil
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
                clipToDelete = nil
            }
        } message: { clip in
            Text("Are you sure you want to delete this clip?")
        }
        .confirmationDialog(
            "Clear All Clips",
            isPresented: $showClearConfirmation
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    do {
                        try await appState.apiClient.clearClips()
                        await loadPage(0)
                        await MainActor.run {
                            showClearConfirmation = false
                            if isInPanel {
                                PanelWindowManager.hidePanel()
                            }
                        }
                    } catch {
                        print("Error clearing clips: \(error)")
                        await MainActor.run {
                            showClearConfirmation = false
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all clips? This action cannot be undone.")
        }
        .onAppear {
            appState.viewActivated()
            Task {
                await loadPage(0)
            }
        }
        .onDisappear {
            // Clean up all modal states
            showDeleteConfirmation = false
            showClearConfirmation = false
            clipToDelete = nil
            appState.viewDeactivated()
        }
        .overlay {
            if showToast {
                ToastView(message: "Content copied! Press Cmd+V to paste")
                    .animation(.easeInOut, value: showToast)
            }
        }
    }
}
