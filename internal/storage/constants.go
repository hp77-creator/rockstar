package storage

import "errors"

const (
	MaxInlineStorageSize = 10 * 1024 * 1024  // 10MB - store in DB
	MaxStorageSize       = 100 * 1024 * 1024 // 100MB - max total size

	TypeText  = "text"
	TypeImage = "image"
	TypeFile  = "file"
)

// Storage errors
var (
	ErrFileTooLarge = errors.New("file size exceeds maximum allowed size")
	ErrInvalidType  = errors.New("invalid content type")
)
