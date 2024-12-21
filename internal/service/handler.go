package service

import "clipboard-manager/pkg/types"

// ClipboardChangeHandler is implemented by components that need to be notified of clipboard changes
type ClipboardChangeHandler interface {
	HandleClipboardChange(clip types.Clip)
}
