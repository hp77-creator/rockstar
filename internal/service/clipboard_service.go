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

// ClipboardService manages clipboard monitoring and storage
type ClipboardService struct {
	monitor clipboard.Monitor
	store   storage.Storage
	ctx     context.Context
	cancel  context.CancelFunc
	wg      sync.WaitGroup
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

// Start begins monitoring and storing clipboard changes
func (s *ClipboardService) Start() error {
	// Set up clipboard change handler
	s.monitor.OnChange(func(clip types.Clip) {
		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			if err := s.handleClipboardChange(clip); err != nil {
				log.Printf("Error handling clipboard change: %v", err)
			}
		}()
	})

	// Start the monitor
	if err := s.monitor.Start(); err != nil {
		return fmt.Errorf("failed to start clipboard monitor: %w", err)
	}

	return nil
}

// Stop gracefully shuts down the service
func (s *ClipboardService) Stop() error {
	// Signal shutdown
	s.cancel()

	// Stop the monitor
	if err := s.monitor.Stop(); err != nil {
		return fmt.Errorf("failed to stop clipboard monitor: %w", err)
	}

	// Wait for ongoing operations to complete
	s.wg.Wait()

	return nil
}

// GetClipByIndex returns the nth most recent clip (0 being the most recent)
func (s *ClipboardService) GetClipByIndex(ctx context.Context, index int) (*types.Clip, error) {
	clips, err := s.store.List(ctx, storage.ListFilter{
		Limit:  index + 1,
		Offset: 0,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get clips: %w", err)
	}

	if len(clips) <= index {
		return nil, fmt.Errorf("no clip found at index %d", index)
	}

	return clips[index], nil
}

// SetClipboard sets the system clipboard to the content of the specified clip
func (s *ClipboardService) SetClipboard(ctx context.Context, clip *types.Clip) error {
	if clip == nil {
		return fmt.Errorf("clip cannot be nil")
	}

	return s.monitor.SetContent(*clip)
}

// PasteByIndex sets the clipboard to the nth most recent clip
func (s *ClipboardService) PasteByIndex(ctx context.Context, index int) error {
	clip, err := s.GetClipByIndex(ctx, index)
	if err != nil {
		return err
	}

	return s.SetClipboard(ctx, clip)
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
		return fmt.Errorf("failed to store clip: %w", err)
	}

	log.Printf("Stored new clipboard content (type: %s, source: %s)", 
		clip.Type, clip.Metadata.SourceApp)

	return nil
}
