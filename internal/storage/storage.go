package storage

import (
	"clipboard-manager/pkg/types"
	"context"
)

// Storage defines the interface for clipboard data persistence
type Storage interface {
	// Store saves clipboard content and returns a clip ID
	Store(ctx context.Context, content []byte, clipType string, metadata types.Metadata) (*types.Clip, error)
	
	// Get retrieves clipboard content by ID
	Get(ctx context.Context, id string) (*types.Clip, error)
	
	// Delete removes clipboard content
	Delete(ctx context.Context, id string) error
	
	// List returns clips matching the filter
	List(ctx context.Context, filter ListFilter) ([]*types.Clip, error)

	// MarkAsSynced marks a clip as synced to Obsidian
	MarkAsSynced(ctx context.Context, id string) error

	// ListUnsynced returns clips that haven't been synced to Obsidian
	ListUnsynced(ctx context.Context, limit int) ([]*types.Clip, error)
}

// ListFilter defines criteria for listing clips
type ListFilter struct {
	Type     string
	Category string
	Tags     []string
	Limit    int
	Offset   int
	SyncedToObsidian *bool // Optional filter for sync status
}

// Config holds storage configuration
type Config struct {
	DBPath  string // Path to SQLite database
	FSPath  string // Path to filesystem storage for large files
}
