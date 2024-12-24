package sqlite

import (
	"clipboard-manager/internal/storage"
	"clipboard-manager/pkg/types"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"gorm.io/gorm"
)

func setupBenchmarkDB(b *testing.B) (*SQLiteStorage, func()) {
	err := os.MkdirAll("./testdata", 0755)
	if err != nil {
		b.Fatal(err)
	}

	dbPath := fmt.Sprintf("./testdata/test_%d.db", time.Now().UnixNano())
	fsPath := fmt.Sprintf("./testdata/fs_%d", time.Now().UnixNano())

	storage, err := New(storage.Config{
		DBPath: dbPath,
		FSPath: fsPath,
	})
	if err != nil {
		b.Fatal(err)
	}

	cleanup := func() {
		if err := storage.Close(); err != nil {
			b.Error(err)
		}
		os.RemoveAll("./testdata")
	}

	return storage, cleanup
}

func generateTestData(size int) []byte {
	data := make([]byte, size)
	for i := range data {
		data[i] = byte(i % 256)
	}
	return data
}

func BenchmarkStore(b *testing.B) {
	storage, cleanup := setupBenchmarkDB(b)
	defer cleanup()

	ctx := context.Background()
	data := generateTestData(1024) // 1KB of test data

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		metadata := types.Metadata{
			SourceApp: "benchmark",
			Category:  "test",
			Tags:      []string{"benchmark", "test"},
		}
		_, err := storage.Store(ctx, data, "text/plain", metadata)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkGet(b *testing.B) {
	storage, cleanup := setupBenchmarkDB(b)
	defer cleanup()

	ctx := context.Background()
	data := generateTestData(1024)
	metadata := types.Metadata{
		SourceApp: "benchmark",
		Category:  "test",
		Tags:      []string{"benchmark", "test"},
	}

	// Store initial data
	clip, err := storage.Store(ctx, data, "text/plain", metadata)
	if err != nil {
		b.Fatal(err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := storage.Get(ctx, fmt.Sprint(clip.ID))
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkList(b *testing.B) {
	storage, cleanup := setupBenchmarkDB(b)
	defer cleanup()

	ctx := context.Background()
	data := generateTestData(1024)

	// Store 100 items
	for i := 0; i < 100; i++ {
		metadata := types.Metadata{
			SourceApp: "benchmark",
			Category:  "test",
			Tags:      []string{"benchmark", "test"},
		}
		_, err := storage.Store(ctx, data, "text/plain", metadata)
		if err != nil {
			b.Fatal(err)
		}
	}

	listFilter := struct {
		Type             string
		Category         string
		Tags             []string
		Limit            int
		Offset           int
		SyncedToObsidian *bool
	}{
		Type:     "",
		Category: "",
		Tags:     nil,
		Limit:    50,
		Offset:   0,
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := storage.List(ctx, listFilter)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkBulkStore(b *testing.B) {
	storage, cleanup := setupBenchmarkDB(b)
	defer cleanup()

	data := generateTestData(1024)
	batchSize := 100

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		err := storage.db.Transaction(func(tx *gorm.DB) error {
			for j := 0; j < batchSize; j++ {
				// Make each record unique by adding a counter to the data
				uniqueData := []byte(fmt.Sprintf("%d-%d-%x", time.Now().UnixNano(), j, data[:32]))
				metadata := types.Metadata{
					SourceApp: fmt.Sprintf("benchmark-%d", j),
					Category:  "test",
					Tags:      []string{"benchmark", "test"},
				}
				// Convert tags to JSON string for storage
				tagsJSON, err := json.Marshal(metadata.Tags)
				if err != nil {
					return fmt.Errorf("failed to marshal tags: %w", err)
				}

				// Use map to avoid GORM struct issues
				model := map[string]interface{}{
					"content":      []byte(uniqueData),
					"type":         "text/plain",
					"source_app":   metadata.SourceApp,
					"category":     metadata.Category,
					"tags":         string(tagsJSON),
					"last_used":    time.Now(),
					"content_hash": calculateHash([]byte(uniqueData)),
					"size":         int64(len(uniqueData)),
					"is_external":  false,
				}
				if err := tx.Table("clip_models").Create(&model).Error; err != nil {
					return err
				}
			}
			return nil
		})
		if err != nil {
			b.Fatal(err)
		}
	}
}
