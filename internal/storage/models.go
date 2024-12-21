package storage

import (
	"clipboard-manager/pkg/types"
	"database/sql/driver"  // Provides interfaces for database interaction
	"encoding/json"        // For JSON encoding/decoding
	"gorm.io/gorm"
	"strconv"
	"time"
)

type JSON json.RawMessage

// StringArray represents a string array that can be stored in SQLite
// We implement sql.Scanner and driver.Valuer interfaces to handle 
// conversion between Go slice and SQLite JSON storage
type StringArray []string

// Scan implements sql.Scanner interface
// This method is called when reading from database
// It converts the stored JSON back into a Go string slice
func (sa *StringArray) Scan(value interface{}) error {
	// Handle nil case (no tags)
	if value == nil {
		*sa = StringArray{}
		return nil
	}

	// Type assertion to handle different input types
	// value could be []byte or string depending on the driver
	var bytes []byte
	switch v := value.(type) {
	case []byte:
		bytes = v
	case string:
		bytes = []byte(v)
	default:
		bytes = []byte{}
	}

	// Convert JSON bytes back to string slice
	return json.Unmarshal(bytes, sa)
}

// Value implements driver.Valuer interface
// This method is called when writing to database
// It converts our string slice into JSON for storage
func (sa StringArray) Value() (driver.Value, error) {
	if sa == nil {
		return nil, nil
	}
	// Convert slice to JSON bytes
	return json.Marshal(sa)
}

// ClipModel represents a clipboard entry in storage
type ClipModel struct {
	gorm.Model
	ContentHash string      `gorm:"type:string;uniqueIndex"` // SHA-256 hash for deduplication
	Content     []byte      `gorm:"type:blob"`              // For inline storage
	StoragePath string      `gorm:"type:string"`            // For filesystem storage
	IsExternal  bool        `gorm:"type:boolean"`           // Whether stored in filesystem
	Size        int64       `gorm:"type:bigint"`            // Content size in bytes
	Type        string      `gorm:"type:string;not null"`
	Metadata    JSON        `gorm:"type:json"`
	SourceApp   string
	Category    string      `gorm:"index"`
	Tags        StringArray `gorm:"type:json"`              // Store as JSON in SQLite
	LastUsed    time.Time   `gorm:"index"`                  // Track when content was last accessed
	SyncedToObsidian bool   `gorm:"type:boolean;default:false"` // Track if synced to Obsidian
}

// ToClip converts ClipModel to public Clip type
func (cm *ClipModel) ToClip() *types.Clip {
	return &types.Clip{
		ID:      strconv.FormatUint(uint64(cm.ID), 10),
		Content: cm.Content,
		Type:    cm.Type,
		Metadata: types.Metadata{
			SourceApp: cm.SourceApp,
			Tags:      cm.Tags,
			Category:  cm.Category,
		},
		CreatedAt: cm.CreatedAt,
	}
}

// FromClip creates a ClipModel from public Clip type
func FromClip(clip *types.Clip) *ClipModel {
	return &ClipModel{
		Content:   clip.Content,
		Type:      clip.Type,
		SourceApp: clip.Metadata.SourceApp,
		Category:  clip.Metadata.Category,
		Tags:      clip.Metadata.Tags,
		LastUsed:  time.Now(),
	}
}

// BeforeSave GORM hook to update LastUsed timestamp
func (cm *ClipModel) BeforeSave(tx *gorm.DB) error {
	cm.LastUsed = time.Now()
	return nil
}
