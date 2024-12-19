package clipboard

import (
	"clipboard-manager/pkg/types"
	"fmt"
	"runtime"
	"sync"
	"time"

	"github.com/progrium/darwinkit/macos/appkit"
)

type DarwinMonitor struct {
	handler     func(types.Clip)
	pasteboard  appkit.Pasteboard
	changeCount int
	mutex       sync.RWMutex
	stopChan    chan struct{}
}

func init() {
	// Ensure we're on the main thread for AppKit operations
	runtime.LockOSThread()
}

func NewMonitor() Monitor {
	// Ensure we're on the main thread for AppKit operations
	runtime.LockOSThread()

	return &DarwinMonitor{
		pasteboard: appkit.Pasteboard_GeneralPasteboard(),
		stopChan:   make(chan struct{}),
	}
}

func (m *DarwinMonitor) Start() error {
	m.mutex.Lock()
	initialCount := m.pasteboard.ChangeCount()
	m.changeCount = initialCount
	m.mutex.Unlock()

	go func() {
		ticker := time.NewTicker(500 * time.Millisecond)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				m.checkForChanges()
			case <-m.stopChan:
				return
			}
		}
	}()

	return nil
}

func (m *DarwinMonitor) Stop() error {
	close(m.stopChan)
	return nil
}

// GetPasteboardTypes returns all available types in the pasteboard
func (m *DarwinMonitor) GetPasteboardTypes() []string {
	m.mutex.RLock()
	defer m.mutex.RUnlock()
	
	var types []string
	for _, t := range m.pasteboard.Types() {
		types = append(types, string(t))
	}
	
	// Add some common types to check if they exist
	commonTypes := []string{
		"com.apple.pasteboard.promised-file-url",
		"com.apple.pasteboard.source",
		"com.apple.pasteboard.app",
		"com.apple.pasteboard.bundleid",
		"com.apple.pasteboard.application-name",
		"com.apple.pasteboard.creator",
		"com.apple.cocoa.pasteboard.source-type",
	}
	
	for _, t := range commonTypes {
		if data := m.pasteboard.StringForType(appkit.PasteboardType(t)); data != "" {
			types = append(types, t+" = "+data)
		}
	}
	
	return types
}

func (m *DarwinMonitor) OnChange(handler func(types.Clip)) {
	m.mutex.Lock()
	m.handler = handler
	m.mutex.Unlock()
}

func (m *DarwinMonitor) checkForChanges() {
	m.mutex.Lock()
	currentCount := m.pasteboard.ChangeCount()
	previousCount := m.changeCount
	m.mutex.Unlock()

	if currentCount != previousCount {
		fmt.Printf("Debug: Clipboard change detected (count: %d -> %d)\n", previousCount, currentCount)
		
		// Get clipboard content
		var clip types.Clip
		clip.CreatedAt = time.Now()
		
		m.mutex.Lock()
		m.changeCount = currentCount
		m.mutex.Unlock()

		// Try different content types in order
		handled := false

		// Check for text content
		if text := m.pasteboard.StringForType(appkit.PasteboardType("public.utf8-plain-text")); text != "" {
			clip.Content = []byte(text)
			clip.Type = "text"
			handled = true
		}

		// Check for screenshot or image content
		if !handled {
			// Try PNG
			if data := m.pasteboard.DataForType(appkit.PasteboardType("public.png")); len(data) > 0 {
				clip.Content = data
				clip.Type = "image/png"
				
				// Check if it's a screenshot by looking for screenshot-specific metadata
				hasWindowID := false
				for _, t := range m.pasteboard.Types() {
					if t == appkit.PasteboardType("com.apple.screencapture.window-id") {
						hasWindowID = true
						break
					}
				}
				if hasWindowID {
					clip.Type = "screenshot"
					if windowTitle := m.pasteboard.StringForType(appkit.PasteboardType("com.apple.screencapture.window-name")); windowTitle != "" {
						clip.Metadata.SourceApp = windowTitle
					}
				}
				
				handled = true
			}
		}

		// Check for TIFF image
		if !handled {
			if data := m.pasteboard.DataForType(appkit.PasteboardType("public.tiff")); len(data) > 0 {
				clip.Content = data
				clip.Type = "image/tiff"
				
				// Similar screenshot check for TIFF
				hasWindowID := false
				for _, t := range m.pasteboard.Types() {
					if t == appkit.PasteboardType("com.apple.screencapture.window-id") {
						hasWindowID = true
						break
					}
				}
				if hasWindowID {
					clip.Type = "screenshot"
					if windowTitle := m.pasteboard.StringForType(appkit.PasteboardType("com.apple.screencapture.window-name")); windowTitle != "" {
						clip.Metadata.SourceApp = windowTitle
					}
				}
				
				handled = true
			}
		}

		// Check for file URLs
		if !handled {
			if urls := m.pasteboard.StringForType(appkit.PasteboardType("public.file-url")); urls != "" {
				clip.Content = []byte(urls)
				clip.Type = "file"
				handled = true
			}
		}

		if handled {
			m.mutex.Lock()
			types := m.pasteboard.Types()
			m.mutex.Unlock()

			// Debug: Print all pasteboard types
			fmt.Println("Debug: Available pasteboard types:")
			for _, t := range types {
				m.mutex.Lock()
				val := m.pasteboard.StringForType(t)
				m.mutex.Unlock()
				
				if val != "" {
					fmt.Printf("  %s = %s\n", t, val)
				} else {
					fmt.Printf("  %s (no string value)\n", t)
				}
			}

			// Try to determine source application using multiple methods
			m.mutex.Lock()
			sourceURL := m.pasteboard.StringForType(appkit.PasteboardType("org.chromium.source-url"))
			m.mutex.Unlock()

			if sourceURL != "" {
				// Content is from a web browser
				if sourceURL != "" {
					clip.Metadata.SourceApp = "Chrome"
					fmt.Printf("Debug: Source from Chrome URL: %s\n", sourceURL)
				}
			} else {
				// Try other methods
				m.mutex.Lock()
				sourceApp := m.pasteboard.StringForType(appkit.PasteboardType("com.apple.pasteboard.app"))
				m.mutex.Unlock()
				
				if sourceApp != "" {
					clip.Metadata.SourceApp = sourceApp
					fmt.Printf("Debug: Source from pasteboard metadata: %s\n", sourceApp)
				} else {
					m.mutex.Lock()
					bundleID := m.pasteboard.StringForType(appkit.PasteboardType("com.apple.pasteboard.bundleid"))
					m.mutex.Unlock()
					
					if bundleID != "" {
						if apps := appkit.RunningApplication_RunningApplicationsWithBundleIdentifier(bundleID); len(apps) > 0 {
							clip.Metadata.SourceApp = apps[0].LocalizedName()
							fmt.Printf("Debug: Source from bundle ID: %s (%s)\n", apps[0].LocalizedName(), bundleID)
						}
					} else if app := appkit.Workspace_SharedWorkspace().FrontmostApplication(); app.LocalizedName() != "" {
						// Only use frontmost app if it's not VS Code (which might just be our active editor)
						if app.BundleIdentifier() != "com.microsoft.VSCode" {
							clip.Metadata.SourceApp = app.LocalizedName()
							fmt.Printf("Debug: Source from frontmost app: %s (%s)\n", 
								app.LocalizedName(), app.BundleIdentifier())
						} else {
							fmt.Printf("Debug: Ignoring VS Code as source\n")
						}
					}
				}
			}
			
			if clip.Metadata.SourceApp == "" {
				fmt.Printf("Debug: Could not determine source application\n")
			}

			if m.handler != nil {
				m.handler(clip)
			}
		}
	}
}
