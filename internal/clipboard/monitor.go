package clipboard

import "clipboard-manager/pkg/types"

type Monitor interface {
	Start() error
	Stop() error
	OnChange(handler func(types.Clip))
}
