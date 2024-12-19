package clipboard

import "clipboard-manager/pkg/types"

type Monitor interface {
	Start() error
	Stop() error
	OnChange(handler func(types.Clip))
	// SetContent sets the system clipboard content
	SetContent(clip types.Clip) error
}
