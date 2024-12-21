package sqlite

import (
	"clipboard-manager/internal/storage"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Search implements storage.SearchService interface
func (s *SQLiteStorage) Search(opts storage.SearchOptions) ([]storage.SearchResult, error) {
	query := s.db.Model(&storage.ClipModel{})

	// Apply text search if query provided
	if opts.Query != "" {
		// Case-insensitive search in content, source app, and metadata
		searchTerm := strings.ToLower(opts.Query)
		
		// First, get all text clips that match the search term
		query = query.Where(
			"(type LIKE 'text%' AND ("+
			"  (is_external = 0 AND LOWER(CAST(content AS TEXT)) LIKE ?) OR "+
			"  LOWER(content_hash) LIKE ?"+
			")) OR "+
			"LOWER(source_app) LIKE ? OR "+
			"LOWER(category) LIKE ? OR "+
			"LOWER(tags) LIKE ?",
			"%"+searchTerm+"%",
			"%"+searchTerm+"%",
			"%"+searchTerm+"%",
			"%"+searchTerm+"%",
			"%"+searchTerm+"%",
		)

		// Also get external text clips
		var externalClips []storage.ClipModel
		s.db.Where("type LIKE 'text%' AND is_external = 1").Find(&externalClips)

		// Search through external content
		for _, clip := range externalClips {
			if content, err := s.loadExternalContent(&clip); err == nil {
				if strings.Contains(strings.ToLower(string(content)), searchTerm) {
					query = query.Or("id = ?", clip.ID)
				}
			}
		}
	}

	// Apply filters
	if opts.Type != "" {
		query = query.Where("type = ?", opts.Type)
	}
	if opts.SourceApp != "" {
		query = query.Where("source_app = ?", opts.SourceApp)
	}
	if opts.Category != "" {
		query = query.Where("category = ?", opts.Category)
	}
	if len(opts.Tags) > 0 {
		for _, tag := range opts.Tags {
			query = query.Where("tags LIKE ?", "%"+tag+"%")
		}
	}

	// Apply time range
	if !opts.From.IsZero() {
		query = query.Where("created_at >= ?", opts.From)
	}
	if !opts.To.IsZero() {
		query = query.Where("created_at <= ?", opts.To)
	}

	// Apply sorting
	if opts.SortBy != "" {
		direction := "DESC"
		if strings.ToLower(opts.SortOrder) == "asc" {
			direction = "ASC"
		}

		switch opts.SortBy {
		case "created_at":
			query = query.Order(fmt.Sprintf("created_at %s", direction))
		case "last_used":
			query = query.Order(fmt.Sprintf("last_used %s", direction))
		}
	} else {
		// Default sort by last used time
		query = query.Order("last_used DESC")
	}

	// Apply pagination
	if opts.Limit > 0 {
		query = query.Limit(opts.Limit)
	}
	if opts.Offset > 0 {
		query = query.Offset(opts.Offset)
	}

	var models []storage.ClipModel
	if err := query.Find(&models).Error; err != nil {
		return nil, fmt.Errorf("failed to search clips: %w", err)
	}

	// Convert to search results
	results := make([]storage.SearchResult, len(models))
	for i, model := range models {
		clip := model.ToClip()

		// Load external content if needed
		if model.IsExternal {
			if content, err := s.loadExternalContent(&model); err == nil {
				clip.Content = content
			}
		}

		results[i] = storage.SearchResult{
			Clip:     clip,
			LastUsed: model.LastUsed,
			// For now, we'll use a simple relevance score based on recency
			Score: float64(model.LastUsed.Unix()),
		}
	}

	return results, nil
}

// GetRecent implements storage.SearchService interface
func (s *SQLiteStorage) GetRecent(limit int) ([]storage.SearchResult, error) {
	return s.Search(storage.SearchOptions{
		Limit:     limit,
		SortBy:    "last_used",
		SortOrder: "desc",
	})
}

// GetMostUsed implements storage.SearchService interface
func (s *SQLiteStorage) GetMostUsed(limit int) ([]storage.SearchResult, error) {
	// For now, we'll use last_used as a proxy for usage frequency
	// In the future, we could add a use_count field to track this properly
	return s.Search(storage.SearchOptions{
		Limit:     limit,
		SortBy:    "last_used",
		SortOrder: "desc",
	})
}

// GetByType implements storage.SearchService interface
func (s *SQLiteStorage) GetByType(clipType string, limit int) ([]storage.SearchResult, error) {
	return s.Search(storage.SearchOptions{
		Type:      clipType,
		Limit:     limit,
		SortBy:    "last_used",
		SortOrder: "desc",
	})
}

// loadExternalContent loads content from filesystem for external storage
func (s *SQLiteStorage) loadExternalContent(model *storage.ClipModel) ([]byte, error) {
	if !model.IsExternal || model.StoragePath == "" {
		return nil, fmt.Errorf("not an external clip")
	}

	return s.readExternalFile(model.StoragePath)
}

// readExternalFile reads a file from the external storage directory
func (s *SQLiteStorage) readExternalFile(filename string) ([]byte, error) {
	path := filepath.Join(s.fsPath, filename)
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read file %s: %w", path, err)
	}
	return content, nil
}
