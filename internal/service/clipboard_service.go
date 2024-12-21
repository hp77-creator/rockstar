package service

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/storage"
	"clipboard-manager/pkg/types"
	"context"
	"fmt"
	"log"
	"sync"
)

// Custom error types for better error handling
type ClipboardError struct {
	Op      string // Operation that failed
	Index   int    // Index involved (if applicable)
	Message string // Error message
	Err     error  // Underlying error
}

func (e *ClipboardError) Error() string {
	if e.Index >= 0 {
		return fmt.Sprintf("%s failed for index %d: %s", e.Op, e.Index, e.Message)
	}
	return fmt.Sprintf("%s failed: %s", e.Op, e.Message)
}

func (e *ClipboardError) Unwrap() error {
	return e.Err
}

// ClipboardService manages clipboard monitoring and storage
type ClipboardService struct {
	monitor  clipboard.Monitor
	store    storage.Storage
	ctx      context.Context
	cancel   context.CancelFunc
	wg       sync.WaitGroup
	handlers []ClipboardChangeHandler
	mu       sync.RWMutex
}

// New creates a new ClipboardService
func New(monitor clipboard.Monitor, store storage.Storage) *ClipboardService {
	ctx, cancel := context.WithCancel(context.Background())
	return &ClipboardService{
		monitor: monitor,
		store:   store,
		ctx:     ctx,
		cancel:  cancel,
	}
}

// RegisterHandler adds a new clipboard change handler
func (s *ClipboardService) RegisterHandler(handler ClipboardChangeHandler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.handlers = append(s.handlers, handler)
}

// Start begins monitoring and storing clipboard changes
func (s *ClipboardService) Start() error {
	// Set up clipboard change handler
	s.monitor.OnChange(func(clip types.Clip) {
		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			if err := s.handleClipboardChange(clip); err != nil {
				log.Printf("Error handling clipboard change: %v", err)
				return
			}
			
			// Notify all registered handlers
			s.mu.RLock()
			handlers := s.handlers // Copy to avoid holding lock during callbacks
			s.mu.RUnlock()
			
			for _, handler := range handlers {
				handler.HandleClipboardChange(clip)
			}
		}()
	})

	// Start the monitor
	if err := s.monitor.Start(); err != nil {
		return &ClipboardError{
			Op:      "Start",
			Index:   -1,
			Message: "failed to start clipboard monitor",
			Err:     err,
		}
	}

	return nil
}

// Stop gracefully shuts down the service
func (s *ClipboardService) Stop() error {
	// Signal shutdown
	s.cancel()

	// Stop the monitor
	if err := s.monitor.Stop(); err != nil {
		return &ClipboardError{
			Op:      "Stop",
			Index:   -1,
			Message: "failed to stop clipboard monitor",
			Err:     err,
		}
	}

	// Wait for ongoing operations to complete
	s.wg.Wait()

	return nil
}

// GetClips returns a paginated list of clips
func (s *ClipboardService) GetClips(ctx context.Context, limit, offset int) ([]*types.Clip, error) {
	clips, err := s.store.List(ctx, storage.ListFilter{
		Limit:  limit,
		Offset: offset,
	})
	if err != nil {
		return nil, &ClipboardError{
			Op:      "GetClips",
			Index:   -1,
			Message: "failed to list clips",
			Err:     err,
		}
	}
	return clips, nil
}

// GetClipByIndex returns the nth most recent clip (0 being the most recent)
func (s *ClipboardService) GetClipByIndex(ctx context.Context, index int) (*types.Clip, error) {
	log.Printf("Getting clip at index %d", index)
	clips, err := s.store.List(ctx, storage.ListFilter{
		Limit:  index + 1,
		Offset: 0,
	})
	if err != nil {
		log.Printf("Error getting clips: %v", err)
		return nil, &ClipboardError{
			Op:      "GetClipByIndex",
			Index:   index,
			Message: "failed to retrieve clips",
			Err:     err,
		}
	}

	log.Printf("Found %d clips", len(clips))
	if len(clips) <= index {
		log.Printf("No clip found at index %d", index)
		return nil, &ClipboardError{
			Op:      "GetClipByIndex",
			Index:   index,
			Message: "clip not found",
			Err:     nil,
		}
	}

	clip := clips[index]
	log.Printf("Retrieved clip - Type: %s, Content Length: %d", clip.Type, len(clip.Content))
	return clip, nil
}

// SetClipboard sets the system clipboard to the content of the specified clip
func (s *ClipboardService) SetClipboard(ctx context.Context, clip *types.Clip) error {
	if clip == nil {
		log.Printf("Error: clip is nil")
		return &ClipboardError{
			Op:      "SetClipboard",
			Index:   -1,
			Message: "clip cannot be nil",
			Err:     nil,
		}
	}

	log.Printf("Setting clipboard - Type: %s, Content Length: %d", clip.Type, len(clip.Content))
	if err := s.monitor.SetContent(*clip); err != nil {
		log.Printf("Error setting clipboard content: %v", err)
		return &ClipboardError{
			Op:      "SetClipboard",
			Index:   -1,
			Message: "failed to set clipboard content",
			Err:     err,
		}
	}
	log.Printf("Successfully set clipboard content")
	return nil
}

// PasteByIndex sets the clipboard to the nth most recent clip
func (s *ClipboardService) PasteByIndex(ctx context.Context, index int) error {
	log.Printf("Paste request for index %d", index)
	clip, err := s.GetClipByIndex(ctx, index)
	if err != nil {
		log.Printf("Error getting clip at index %d: %v", index, err)
		return &ClipboardError{
			Op:      "PasteByIndex",
			Index:   index,
			Message: "failed to retrieve clip",
			Err:     err,
		}
	}

	log.Printf("Found clip at index %d - Type: %s, Content Length: %d", index, clip.Type, len(clip.Content))
	if err := s.SetClipboard(ctx, clip); err != nil {
		log.Printf("Error setting clipboard: %v", err)
		return &ClipboardError{
			Op:      "PasteByIndex",
			Index:   index,
			Message: "failed to set clipboard content",
			Err:     err,
		}
	}
	log.Printf("Successfully pasted clip at index %d", index)
	return nil
}

// handleClipboardChange processes and stores clipboard content
func (s *ClipboardService) handleClipboardChange(clip types.Clip) error {
	// Skip empty content
	if len(clip.Content) == 0 {
		return nil
	}

	// Store the clip
	_, err := s.store.Store(s.ctx, clip.Content, clip.Type, clip.Metadata)
	if err == storage.ErrFileTooLarge {
		log.Printf("Content too large to store (size: %d bytes)", len(clip.Content))
		return nil
	} else if err != nil {
		return &ClipboardError{
			Op:      "handleClipboardChange",
			Index:   -1,
			Message: "failed to store clip",
			Err:     err,
		}
	}

	log.Printf("Stored new clipboard content (type: %s, source: %s)", 
		clip.Type, clip.Metadata.SourceApp)

	return nil
}
