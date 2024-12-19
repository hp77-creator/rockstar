package storage

import (
	"clipboard-manager/pkg/types"
	"time"
)

// SearchOptions defines criteria for searching clips
type SearchOptions struct {
	// Text search query
	Query string

	// Filter by content type
	Type string

	// Filter by source application
	SourceApp string

	// Filter by category
	Category string

	// Filter by tags (all tags must match)
	Tags []string

	// Time range
	From time.Time
	To   time.Time

	// Pagination
	Limit  int
	Offset int

	// Sort options
	SortBy    string // "created_at", "last_used"
	SortOrder string // "asc", "desc"
}

// SearchResult represents a search result with metadata
type SearchResult struct {
	// The matching clip
	Clip *types.Clip

	// Search result metadata
	Score     float64   // Relevance score
	Matches   []string  // Matched terms
	LastUsed  time.Time // When this clip was last accessed
	UseCount  int       // Number of times this clip was accessed
}

// SearchService defines the interface for searching clips
type SearchService interface {
	// Search returns clips matching the given criteria
	Search(opts SearchOptions) ([]SearchResult, error)

	// GetRecent returns the most recently used clips
	GetRecent(limit int) ([]SearchResult, error)

	// GetMostUsed returns the most frequently used clips
	GetMostUsed(limit int) ([]SearchResult, error)

	// GetByType returns clips of a specific type
	GetByType(clipType string, limit int) ([]SearchResult, error)
}
