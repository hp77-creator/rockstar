package types

import "time"

type Clip struct {
	ID        string
	Content   []byte
	Type      string // supported types -> text, image, file(will have to check)
	Metadata  Metadata
	CreatedAt time.Time
}

type Metadata struct {
	SourceApp string
	Tags      []string
	Category  string
}
