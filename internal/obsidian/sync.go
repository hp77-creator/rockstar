package obsidian

import (
	"clipboard-manager/internal/storage"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// SyncService handles syncing clipboard content to Obsidian vault
type SyncService struct {
	store      storage.Storage
	vaultPath  string
	syncTicker *time.Ticker
	done       chan struct{}
	mu         sync.RWMutex // Protects vaultPath
}

// UpdateVaultPath updates the vault path while the service is running
func (s *SyncService) UpdateVaultPath(path string) error {
	// Verify new path exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("new vault path does not exist: %s", path)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	log.Printf("Updating vault path from %s to %s", s.vaultPath, path)
	s.vaultPath = path
	return nil
}

// Config holds configuration for the Obsidian sync service
type Config struct {
	VaultPath    string
	SyncInterval time.Duration
}

// New creates a new Obsidian sync service
func New(store storage.Storage, config Config) (*SyncService, error) {
	if config.VaultPath == "" {
		return nil, fmt.Errorf("vault path is required")
	}

	// Verify vault path exists
	if _, err := os.Stat(config.VaultPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("vault path does not exist: %s", config.VaultPath)
	}

	// Validate sync interval
	if config.SyncInterval <= 0 {
		return nil, fmt.Errorf("sync interval must be positive, got: %v", config.SyncInterval)
	}

	return &SyncService{
		store:      store,
		vaultPath:  config.VaultPath,
		syncTicker: time.NewTicker(config.SyncInterval),
		done:       make(chan struct{}),
	}, nil
}

// Start begins the sync service
func (s *SyncService) Start(ctx context.Context) error {
	log.Printf("Starting Obsidian sync service (vault: %s)", s.vaultPath)

	// Perform initial sync
	if err := s.sync(ctx); err != nil {
		log.Printf("Initial sync error: %v", err)
	}

	go func() {
		for {
			select {
			case <-ctx.Done():
				log.Printf("Obsidian sync service stopped (context done)")
				return
			case <-s.done:
				log.Printf("Obsidian sync service stopped (done signal)")
				return
			case <-s.syncTicker.C:
				log.Printf("Running scheduled sync...")
				if err := s.sync(ctx); err != nil {
					log.Printf("Error during sync: %v", err)
				}
			}
		}
	}()

	return nil
}

// Stop stops the sync service
func (s *SyncService) Stop() {
	log.Printf("Stopping Obsidian sync service")
	if s.syncTicker != nil {
		s.syncTicker.Stop()
	}
	select {
	case <-s.done:
		// Already closed
	default:
		close(s.done)
	}
	log.Printf("Obsidian sync service stopped")
}

// UpdateSyncInterval updates the sync interval while the service is running
func (s *SyncService) UpdateSyncInterval(interval time.Duration) {
	if interval <= 0 {
		log.Printf("Warning: Ignoring non-positive sync interval: %v", interval)
		return
	}
	log.Printf("Updating sync interval to %v", interval)
	if s.syncTicker != nil {
		s.syncTicker.Reset(interval)
	}
}

// sync performs the actual synchronization
func (s *SyncService) sync(ctx context.Context) error {
	log.Printf("Starting sync operation in vault: %s", s.vaultPath)
	
	// Get current vault path (thread-safe)
	s.mu.RLock()
	vaultPath := s.vaultPath
	s.mu.RUnlock()

	// Verify vault path still exists and is accessible
	if info, err := os.Stat(vaultPath); err != nil {
		return fmt.Errorf("vault path error: %w", err)
	} else {
		log.Printf("Vault path verified: %s (%s)", vaultPath, info.Mode())
	}
	
	// Get unsynced clips
	clips, err := s.store.ListUnsynced(ctx, 100) // Adjust limit as needed
	if err != nil {
		return fmt.Errorf("failed to list clips: %w", err)
	}
	log.Printf("Found %d clips to process", len(clips))

	for _, clip := range clips {
		// Process clip content
		log.Printf("Processing clip - ID: %s, Type: %s", clip.ID, clip.Type)
		
		// Convert content bytes to string
		content := string(clip.Content)
		if content == "" {
			log.Printf("Skipping empty content")
			continue
		}
		log.Printf("Content length: %d bytes", len(content))

		// Generate filename based on date
		filename := fmt.Sprintf("%s.md", clip.CreatedAt.Format("2006-01-02"))
		clipboardDir := filepath.Join(vaultPath, "Clipboard")
		path := filepath.Join(clipboardDir, filename)

		log.Printf("File operations:")
		log.Printf("- Filename: %s", filename)
		log.Printf("- Clipboard dir: %s", clipboardDir)
		log.Printf("- Full path: %s", path)

		// Ensure Clipboard directory exists with proper permissions
		if err := os.MkdirAll(clipboardDir, 0755); err != nil {
			log.Printf("Failed to create directory: %v", err)
			return fmt.Errorf("failed to create directory: %w", err)
		}

		// Verify directory permissions
		if info, err := os.Stat(clipboardDir); err != nil {
			log.Printf("Failed to verify directory: %v", err)
			return fmt.Errorf("failed to verify directory: %w", err)
		} else {
			log.Printf("Directory permissions: %v", info.Mode().Perm())
			if info.Mode().Perm()&0200 == 0 { // Check write permission
				log.Printf("Warning: No write permission on directory")
				return fmt.Errorf("no write permission on directory: %s", clipboardDir)
			}
		}
		log.Printf("Clipboard directory created/verified with write permissions")

		// Get tags from metadata
		tags := clip.Metadata.Tags
		log.Printf("Tags: %v", tags)

		// Generate entry content based on type
		var entryContent string
		if strings.HasPrefix(clip.Type, "image/") {
			// Create assets directory if it doesn't exist
			assetsDir := filepath.Join(clipboardDir, "assets")
			if err := os.MkdirAll(assetsDir, 0755); err != nil {
				log.Printf("Failed to create assets directory: %v", err)
				return fmt.Errorf("failed to create assets directory: %w", err)
			}

			// Generate unique image filename using timestamp
			imageFilename := fmt.Sprintf("%s-%s%s",
				clip.CreatedAt.Format("20060102-150405"),
				clip.ID,
				s.getImageExtension(clip.Type))
			imagePath := filepath.Join(assetsDir, imageFilename)

			// Save image file
			if err := os.WriteFile(imagePath, clip.Content, 0644); err != nil {
				log.Printf("Failed to write image file: %v", err)
				return fmt.Errorf("failed to write image file: %w", err)
			}

			// Use relative path for markdown
			relImagePath := filepath.Join("assets", imageFilename)
			entryContent = fmt.Sprintf("![[%s]]", relImagePath)
		} else {
			entryContent = content
		}

		// Generate entry with metadata and content
		entry := fmt.Sprintf(`
## %s
---
source: %s
tags: [clipboard%s]
type: %s
---

%s

`,
			clip.CreatedAt.Format("15:04:05"),
			clip.Metadata.SourceApp,
			s.formatTags(tags),
			clip.Type,
			entryContent)

		var fileContent string
		if _, err := os.Stat(path); os.IsNotExist(err) {
			// Create new file with date heading
			fileContent = fmt.Sprintf("# %s\n%s", 
				clip.CreatedAt.Format("2006-01-02"),
				entry)
		} else {
			// Read existing file
			existingContent, err := os.ReadFile(path)
			if err != nil {
				log.Printf("Failed to read existing file: %v", err)
				return fmt.Errorf("failed to read existing file: %w", err)
			}
			fileContent = string(existingContent) + entry
		}

		// Write to file with explicit permissions
		log.Printf("Writing/Updating note: %s", path)
		if err := os.WriteFile(path, []byte(fileContent), 0644); err != nil {
			log.Printf("Failed to write file: %v", err)
			return fmt.Errorf("failed to write file: %w", err)
		}

		// Verify file was created with correct permissions
		if info, err := os.Stat(path); err != nil {
			log.Printf("Failed to verify file: %v", err)
			return fmt.Errorf("failed to verify file: %w", err)
		} else {
			log.Printf("File created with permissions: %v", info.Mode().Perm())
		}

		log.Printf("Successfully created note: %s", filename)

		// Mark clip as synced
		if err := s.store.MarkAsSynced(ctx, clip.ID); err != nil {
			log.Printf("Failed to mark clip as synced: %v", err)
			return fmt.Errorf("failed to mark clip as synced: %w", err)
		}
		log.Printf("Marked clip %s as synced", clip.ID)
	}

	log.Printf("Sync operation completed")
	return nil
}

// getImageExtension returns the appropriate file extension based on MIME type
func (s *SyncService) getImageExtension(mimeType string) string {
	switch mimeType {
	case "image/png":
		return ".png"
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "image/svg+xml":
		return ".svg"
	default:
		return ".png" // default to png if unknown
	}
}

// formatTags formats tags for frontmatter
func (s *SyncService) formatTags(tags []string) string {
	if len(tags) == 0 {
		return ""
	}

	var formattedTags []string
	for _, tag := range tags {
		// Clean tag: remove spaces and special characters
		cleanTag := strings.Map(func(r rune) rune {
			if r == ' ' {
				return '-'
			}
			return r
		}, tag)
		formattedTags = append(formattedTags, cleanTag)
	}

	return ", " + strings.Join(formattedTags, ", ")
}
