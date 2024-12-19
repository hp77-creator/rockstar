package examples

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/service"
	"clipboard-manager/internal/storage"
	"clipboard-manager/internal/storage/sqlite"
	"clipboard-manager/pkg/types"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
)

// Example shows how to use the clipboard manager core functionality
func Example() {
	// 1. Set up storage
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatal(err)
	}

	baseDir := filepath.Join(homeDir, ".clipboard-manager")
	store, err := sqlite.New(storage.Config{
		DBPath: filepath.Join(baseDir, "clipboard.db"),
		FSPath: filepath.Join(baseDir, "files"),
	})
	if err != nil {
		log.Fatal(err)
	}

	// 2. Create clipboard monitor
	monitor := clipboard.NewMonitor()

	// 3. Create clipboard service
	clipService := service.New(monitor, store)

	// 4. Start monitoring clipboard
	if err := clipService.Start(); err != nil {
		log.Fatal(err)
	}
	defer clipService.Stop()

	// 5. Search functionality example
	results, err := store.Search(storage.SearchOptions{
		Query:     "example",           // Search for specific content
		Type:      storage.TypeText,    // Filter by type
		SortBy:    "last_used",        // Sort by timestamp
		SortOrder: "desc",             // Most recent first
		Limit:     10,                 // Limit results
	})
	if err != nil {
		log.Fatal(err)
	}

	// 6. Process search results
	for _, result := range results {
		fmt.Printf("Found clip: %s (type: %s)\n", 
			string(result.Clip.Content),
			result.Clip.Type,
		)
	}

	// 7. Get recent clips
	recent, err := store.GetRecent(5)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Recent clips: %d\n", len(recent))

	// 8. Get clips by type
	images, err := store.GetByType(storage.TypeImage, 5)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Recent images: %d\n", len(images))

	// 9. Manual clipboard operations
	ctx := context.Background()
	content := []byte("Example content")
	metadata := types.Metadata{
		SourceApp: "Example App",
		Category:  "Example",
		Tags:      []string{"example", "test"},
	}

	// Store new content
	clip, err := store.Store(ctx, content, storage.TypeText, metadata)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Stored clip with ID: %s\n", clip.ID)

	// Retrieve content
	retrieved, err := store.Get(ctx, clip.ID)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Retrieved clip: %s\n", string(retrieved.Content))

	// Delete content
	if err := store.Delete(ctx, clip.ID); err != nil {
		log.Fatal(err)
	}
	fmt.Println("Deleted clip")

	// 10. Clipboard history operations
	// Get the second most recent clip (index 1)
	if err := clipService.PasteByIndex(ctx, 1); err != nil {
		log.Printf("Failed to paste clip: %v", err)
	}

	// Get a specific clip and set it as current clipboard content
	if clip, err := clipService.GetClipByIndex(ctx, 0); err == nil {
		if err := clipService.SetClipboard(ctx, clip); err != nil {
			log.Printf("Failed to set clipboard: %v", err)
		}
	}
}

// CustomStorage shows how to implement a custom storage backend
type CustomStorage struct {
	// Your storage fields
}

func (s *CustomStorage) Store(ctx context.Context, content []byte, clipType string, metadata types.Metadata) (*types.Clip, error) {
	// Your implementation
	return nil, nil
}

func (s *CustomStorage) Get(ctx context.Context, id string) (*types.Clip, error) {
	// Your implementation
	return nil, nil
}

func (s *CustomStorage) Delete(ctx context.Context, id string) error {
	// Your implementation
	return nil
}

func (s *CustomStorage) List(ctx context.Context, filter storage.ListFilter) ([]*types.Clip, error) {
	// Your implementation
	return nil, nil
}

// CustomMonitor shows how to implement a custom clipboard monitor
type CustomMonitor struct {
	// Your monitor fields
}

func (m *CustomMonitor) Start() error {
	// Your implementation
	return nil
}

func (m *CustomMonitor) Stop() error {
	// Your implementation
	return nil
}

func (m *CustomMonitor) OnChange(handler func(types.Clip)) {
	// Your implementation
}

func (m *CustomMonitor) SetContent(clip types.Clip) error {
	// Your implementation
	return nil
}

// ExampleCustomImplementation shows how to use custom storage and monitor
func ExampleCustomImplementation() {
	// Create custom components
	store := &CustomStorage{}
	monitor := &CustomMonitor{}

	// Create service with custom components
	clipService := service.New(monitor, store)

	// Use the service as normal
	if err := clipService.Start(); err != nil {
		log.Fatal(err)
	}
	defer clipService.Stop()
}
