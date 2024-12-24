import Foundation
import SwiftUI

actor SearchManager {
    private var searchTask: Task<Void, Never>?
    private let pageSize: Int
    
    init(pageSize: Int = 20) {
        self.pageSize = pageSize
    }
    
    func cancelCurrentSearch() {
        searchTask?.cancel()
    }
    
    private func performLocalSearch(in clips: [ClipboardItem], searchTerm: String) -> [ClipboardItem] {
        clips.filter { clip in
            if let text = clip.contentString?.lowercased(),
               text.contains(searchTerm) {
                return true
            }
            if let sourceApp = clip.metadata.sourceApp?.lowercased(),
               sourceApp.contains(searchTerm) {
                return true
            }
            if let category = clip.metadata.category?.lowercased(),
               category.contains(searchTerm) {
                return true
            }
            if let tags = clip.metadata.tags,
               tags.contains(where: { $0.lowercased().contains(searchTerm) }) {
                return true
            }
            return false
        }
    }
    
    func search(
        query: String,
        in clips: [ClipboardItem],
        apiClient: APIClient
    ) async -> ClipboardSearchResult {
        cancelCurrentSearch()
        
        if query.isEmpty {
            return .resetToInitial
        }
        
        // Add debounce delay
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        if Task.isCancelled { return .cancelled }
        
        let searchTerm = query.lowercased()
        let localResults = performLocalSearch(in: clips, searchTerm: searchTerm)
        
        if Task.isCancelled { return .cancelled }
        
        if !localResults.isEmpty {
            return .localResults(localResults)
        }
        
        // Perform backend search if no local results
        do {
            let results = try await apiClient.searchClips(
                query: query,
                offset: 0,
                limit: pageSize
            )
            if Task.isCancelled { return .cancelled }
            return .backendResults(results, hasMore: results.count == pageSize)
        } catch {
            Logger.error("Search error: \(error)")
            return .error(error)
        }
    }
}

enum ClipboardSearchResult {
    case localResults([ClipboardItem])
    case backendResults([ClipboardItem], hasMore: Bool)
    case resetToInitial
    case cancelled
    case error(Error)
}

// Extension to handle search state updates
extension ClipboardSearchResult {
    func updateState(_ state: inout SearchState) {
        switch self {
        case .localResults(let results):
            state.clips = results
            state.selectedIndex = 0
            state.hasMoreContent = false  // Disable pagination for local results
            state.currentPage = 0
            state.isSearching = false
            
        case .backendResults(let results, let hasMore):
            state.clips = results
            state.selectedIndex = 0
            state.hasMoreContent = hasMore
            state.currentPage = 0
            state.isSearching = false
            
        case .resetToInitial:
            state.isSearching = false
            state.currentPage = 0
            state.hasMoreContent = true
            // Note: Initial page load should be handled separately
            
        case .cancelled:
            state.isSearching = false
            
        case .error:
            state.isSearching = false
            // Could add error state handling here if needed
        }
    }
}

// State container for search-related state
struct SearchState {
    var clips: [ClipboardItem]
    var selectedIndex: Int
    var currentPage: Int
    var hasMoreContent: Bool
    var isSearching: Bool
    
    static func initial() -> SearchState {
        SearchState(
            clips: [],
            selectedIndex: 0,
            currentPage: 0,
            hasMoreContent: true,
            isSearching: false
        )
    }
}
