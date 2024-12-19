package sqlite

import (
	"clipboard-manager/internal/storage"
	"clipboard-manager/pkg/types"
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func setupTestDB(t *testing.T) (*SQLiteStorage, func()) {
	// Create temp directories for test
	tempDir, err := os.MkdirTemp("", "clipboard-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}

	dbPath := filepath.Join(tempDir, "test.db")
	fsPath := filepath.Join(tempDir, "files")

	// Initialize storage
	store, err := New(storage.Config{
		DBPath: dbPath,
		FSPath: fsPath,
	})
	if err != nil {
		os.RemoveAll(tempDir)
		t.Fatalf("failed to create storage: %v", err)
	}

	// Return cleanup function
	cleanup := func() {
		os.RemoveAll(tempDir)
	}

	return store, cleanup
}

func TestStore_BasicOperations(t *testing.T) {
	store, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	content := []byte("test content")
	metadata := types.Metadata{
		SourceApp: "test",
		Category: "test",
		Tags: []string{"test"},
	}

	// Test Store
	clip, err := store.Store(ctx, content, storage.TypeText, metadata)
	if err != nil {
		t.Fatalf("failed to store clip: %v", err)
	}
	if clip.ID == "" {
		t.Error("clip ID should not be empty")
	}

	// Test Get
	retrieved, err := store.Get(ctx, clip.ID)
	if err != nil {
		t.Fatalf("failed to get clip: %v", err)
	}
	if string(retrieved.Content) != string(content) {
		t.Errorf("content mismatch: got %s, want %s", retrieved.Content, content)
	}

	// Test List
	clips, err := store.List(ctx, storage.ListFilter{
		Type: storage.TypeText,
		Limit: 10,
	})
	if err != nil {
		t.Fatalf("failed to list clips: %v", err)
	}
	if len(clips) != 1 {
		t.Errorf("expected 1 clip, got %d", len(clips))
	}

	// Test Delete
	if err := store.Delete(ctx, clip.ID); err != nil {
		t.Fatalf("failed to delete clip: %v", err)
	}

	// Verify deletion
	_, err = store.Get(ctx, clip.ID)
	if err == nil {
		t.Error("expected error getting deleted clip")
	}
}

func TestStore_Deduplication(t *testing.T) {
	store, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	content := []byte("duplicate content")
	metadata := types.Metadata{
		SourceApp: "test",
		Category: "test",
	}

	// Store first copy
	clip1, err := store.Store(ctx, content, storage.TypeText, metadata)
	if err != nil {
		t.Fatalf("failed to store first clip: %v", err)
	}

	// Small delay to ensure different timestamps
	time.Sleep(time.Millisecond * 100)

	// Store duplicate content
	clip2, err := store.Store(ctx, content, storage.TypeText, metadata)
	if err != nil {
		t.Fatalf("failed to store second clip: %v", err)
	}

	if clip1.ID != clip2.ID {
		t.Error("deduplication failed: got different IDs for same content")
	}

	// Verify LastUsed was updated
	var model storage.ClipModel
	if err := store.db.First(&model, clip1.ID).Error; err != nil {
		t.Fatalf("failed to get clip model: %v", err)
	}

	if !model.LastUsed.After(clip1.CreatedAt) {
		t.Error("LastUsed timestamp was not updated")
	}
}

func TestStore_SizeLimits(t *testing.T) {
	store, cleanup := setupTestDB(t)
	defer cleanup()

	ctx := context.Background()
	metadata := types.Metadata{SourceApp: "test"}

	// Test file too large
	largeContent := make([]byte, storage.MaxStorageSize+1)
	_, err := store.Store(ctx, largeContent, storage.TypeFile, metadata)
	if err != storage.ErrFileTooLarge {
		t.Errorf("expected ErrFileTooLarge, got %v", err)
	}

	// Test file stored in filesystem
	mediumContent := make([]byte, storage.MaxInlineStorageSize+1)
	clip, err := store.Store(ctx, mediumContent, storage.TypeFile, metadata)
	if err != nil {
		t.Fatalf("failed to store medium file: %v", err)
	}

	// Verify content is stored externally
	var model storage.ClipModel
	if err := store.db.First(&model, clip.ID).Error; err != nil {
		t.Fatalf("failed to get clip model: %v", err)
	}
	if !model.IsExternal {
		t.Error("content should be stored externally")
	}
	if model.StoragePath == "" {
		t.Error("storage path should not be empty")
	}

	// Verify content can be retrieved
	retrieved, err := store.Get(ctx, clip.ID)
	if err != nil {
		t.Fatalf("failed to get clip: %v", err)
	}
	if len(retrieved.Content) != len(mediumContent) {
		t.Errorf("content length mismatch: got %d, want %d", len(retrieved.Content), len(mediumContent))
	}
}
