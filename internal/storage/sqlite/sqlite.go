package sqlite

import (
	"clipboard-manager/internal/storage"
	"clipboard-manager/pkg/types"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type SQLiteStorage struct {
	db     *gorm.DB
	fsPath string // Base path for file system storage
}

// New creates a new SQLite storage instance with optimized configuration
func New(config storage.Config) (*SQLiteStorage, error) {
	// Open database with WAL mode enabled
	db, err := gorm.Open(sqlite.Open(config.DBPath), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Get the underlying *sql.DB instance
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get underlying *sql.DB: %w", err)
	}

	// Configure connection pool
	sqlDB.SetMaxOpenConns(1)  // SQLite only supports one writer at a time
	sqlDB.SetMaxIdleConns(1)
	sqlDB.SetConnMaxLifetime(time.Hour)

	// Auto-migrate the schema first
	if err := db.AutoMigrate(&storage.ClipModel{}); err != nil {
		return nil, fmt.Errorf("failed to migrate schema: %w", err)
	}

	// Apply performance optimizations
	if err := db.Exec(`
		-- Enable WAL mode for better concurrency and performance
		PRAGMA journal_mode = WAL;
		
		-- NORMAL provides good durability with better performance
		-- In WAL mode, NORMAL is safe as WAL provides durability
		PRAGMA synchronous = NORMAL;
		
		-- Increase cache size to 16MB (4000 pages * 4KB per page)
		PRAGMA cache_size = -4000;
		
		-- Enable memory-mapped I/O for reading
		PRAGMA mmap_size = 268435456;  -- 256MB
		
		-- Set busy timeout to 5 seconds
		PRAGMA busy_timeout = 5000;
		
		-- Enable foreign key constraints
		PRAGMA foreign_keys = ON;
	`).Error; err != nil {
		return nil, fmt.Errorf("failed to set PRAGMA options: %w", err)
	}

	// Create indexes after table creation
	if err := db.Exec(`
		CREATE INDEX IF NOT EXISTS idx_clips_content_hash ON clip_models(content_hash);
		CREATE INDEX IF NOT EXISTS idx_clips_last_used ON clip_models(last_used);
	`).Error; err != nil {
		return nil, fmt.Errorf("failed to create indexes: %w", err)
	}

	// Create storage directory if it doesn't exist
	if err := os.MkdirAll(config.FSPath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create storage directory: %w", err)
	}

	return &SQLiteStorage{
		db:     db,
		fsPath: config.FSPath,
	}, nil
}

// calculateHash generates SHA-256 hash of content
func calculateHash(content []byte) string {
	hash := sha256.Sum256(content)
	return hex.EncodeToString(hash[:])
}

// Close closes the database connection and cleans up WAL files
func (s *SQLiteStorage) Close() error {
	sqlDB, err := s.db.DB()
	if err != nil {
		return fmt.Errorf("failed to get underlying *sql.DB: %w", err)
	}

	// Checkpoint WAL file and merge it with the main database
	if err := s.db.Exec("PRAGMA wal_checkpoint(TRUNCATE);").Error; err != nil {
		return fmt.Errorf("failed to checkpoint WAL: %w", err)
	}

	// Close database connection
	if err := sqlDB.Close(); err != nil {
		return fmt.Errorf("failed to close database: %w", err)
	}

	return nil
}

// Store implements storage.Storage interface
func (s *SQLiteStorage) Store(ctx context.Context, content []byte, clipType string, metadata types.Metadata) (*types.Clip, error) {
	size := int64(len(content))
	if size > storage.MaxStorageSize {
		return nil, storage.ErrFileTooLarge
	}

	// Calculate content hash
	contentHash := calculateHash(content)

	// Check for existing content with same hash
	var existing storage.ClipModel
	if err := s.db.Where("content_hash = ?", contentHash).First(&existing).Error; err == nil {
		// Content exists, update LastUsed timestamp
		existing.LastUsed = time.Now()
		if err := s.db.Save(&existing).Error; err != nil {
			return nil, fmt.Errorf("failed to update existing clip: %w", err)
		}
		return existing.ToClip(), nil
	} else if err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to check for existing content: %w", err)
	}

	// Create new clip model
	model := &storage.ClipModel{
		ContentHash: contentHash,
		Type:       clipType,
		Size:       size,
		SourceApp:  metadata.SourceApp,
		Category:   metadata.Category,
		Tags:       metadata.Tags,
		LastUsed:   time.Now(),
	}

	if size > storage.MaxInlineStorageSize {
		// Store in filesystem
		filename := contentHash
		path := filepath.Join(s.fsPath, filename)

		if err := os.WriteFile(path, content, 0644); err != nil {
			return nil, fmt.Errorf("failed to write file: %w", err)
		}

		model.StoragePath = filename
		model.IsExternal = true
	} else {
		// Store in database
		model.Content = content
	}

	if err := s.db.Create(model).Error; err != nil {
		return nil, fmt.Errorf("failed to create clip: %w", err)
	}

	return model.ToClip(), nil
}

// Get implements storage.Storage interface
func (s *SQLiteStorage) Get(ctx context.Context, id string) (*types.Clip, error) {
	var model storage.ClipModel
	if err := s.db.First(&model, id).Error; err != nil {
		return nil, fmt.Errorf("failed to get clip: %w", err)
	}

	// Load external content if needed
	if model.IsExternal {
		path := filepath.Join(s.fsPath, model.StoragePath)
		content, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("failed to read external content: %w", err)
		}
		model.Content = content
	}

	// Update LastUsed timestamp
	model.LastUsed = time.Now()
	if err := s.db.Save(&model).Error; err != nil {
		return nil, fmt.Errorf("failed to update last used time: %w", err)
	}

	return model.ToClip(), nil
}

// Delete implements storage.Storage interface
func (s *SQLiteStorage) Delete(ctx context.Context, id string) error {
	var model storage.ClipModel
	if err := s.db.First(&model, id).Error; err != nil {
		return fmt.Errorf("failed to get clip: %w", err)
	}

	// Delete external file if exists
	if model.IsExternal {
		path := filepath.Join(s.fsPath, model.StoragePath)
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("failed to delete external file: %w", err)
		}
	}

	if err := s.db.Delete(&model).Error; err != nil {
		return fmt.Errorf("failed to delete clip: %w", err)
	}

	return nil
}

// List implements storage.Storage interface
func (s *SQLiteStorage) List(ctx context.Context, filter storage.ListFilter) ([]*types.Clip, error) {
	query := s.db.Model(&storage.ClipModel{})

	if filter.Type != "" {
		query = query.Where("type = ?", filter.Type)
	}
	if filter.Category != "" {
		query = query.Where("category = ?", filter.Category)
	}
	if len(filter.Tags) > 0 {
		query = query.Where("tags @> ?", filter.Tags)
	}

	// Apply pagination
	if filter.Limit > 0 {
		query = query.Limit(filter.Limit)
	}
	if filter.Offset > 0 {
		query = query.Offset(filter.Offset)
	}

	// Order by last used time to show most recent clips first
	query = query.Order("last_used DESC")

	var models []storage.ClipModel
	if err := query.Find(&models).Error; err != nil {
		return nil, fmt.Errorf("failed to list clips: %w", err)
	}

	clips := make([]*types.Clip, len(models))
	for i, model := range models {
		// Load external content if needed
		if model.IsExternal {
			path := filepath.Join(s.fsPath, model.StoragePath)
			content, err := os.ReadFile(path)
			if err != nil {
				return nil, fmt.Errorf("failed to read external content for clip %d: %w", model.ID, err)
			}
			model.Content = content
		}
		clips[i] = model.ToClip()
	}

	return clips, nil
}

// MarkAsSynced implements storage.Storage interface
func (s *SQLiteStorage) MarkAsSynced(ctx context.Context, id string) error {
	result := s.db.Model(&storage.ClipModel{}).
		Where("id = ?", id).
		Update("synced_to_obsidian", true)
	
	if result.Error != nil {
		return fmt.Errorf("failed to mark clip as synced: %w", result.Error)
	}
	
	if result.RowsAffected == 0 {
		return fmt.Errorf("no clip found with id: %s", id)
	}
	
	return nil
}

// ListUnsynced implements storage.Storage interface
func (s *SQLiteStorage) ListUnsynced(ctx context.Context, limit int) ([]*types.Clip, error) {
	var models []storage.ClipModel
	
	query := s.db.Model(&storage.ClipModel{}).
		Where("synced_to_obsidian = ?", false).
		Order("created_at DESC")
	
	if limit > 0 {
		query = query.Limit(limit)
	}
	
	if err := query.Find(&models).Error; err != nil {
		return nil, fmt.Errorf("failed to list unsynced clips: %w", err)
	}

	clips := make([]*types.Clip, len(models))
	for i, model := range models {
		// Load external content if needed
		if model.IsExternal {
			path := filepath.Join(s.fsPath, model.StoragePath)
			content, err := os.ReadFile(path)
			if err != nil {
				return nil, fmt.Errorf("failed to read external content for clip %d: %w", model.ID, err)
			}
			model.Content = content
		}
		clips[i] = model.ToClip()
	}

	return clips, nil
}
