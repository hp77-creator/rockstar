package storage

import (
	"clipboard-manager/pkg/types"
	"encoding/json"
	"gorm.io/gorm"
	"strconv"
)

type JSON json.RawMessage
type StringArray []string

type ClipModel struct {
	gorm.Model
	Content   []byte `gorm:"type:blob;not null"`
	Type      string `gorm:"type:string;not null"`
	Metadata  JSON   `gorm:"type:json"`
	SourceApp string
	Category  string      `gorm:"index"`
	Tags      StringArray `gorm:"type:text[]"`
}

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

func FromClipModel(clipModel *types.Clip) *ClipModel {
	return &ClipModel{
		Content:   clipModel.Content,
		Type:      clipModel.Type,
		SourceApp: clipModel.Metadata.SourceApp,
		Category:  clipModel.Metadata.Category,
		Tags:      clipModel.Metadata.Tags,
	}
}
