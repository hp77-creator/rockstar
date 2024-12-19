package main

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/pkg/types"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	monitor := clipboard.NewMonitor()

	// Set up clipboard change handler
	monitor.OnChange(func(clip types.Clip) {
		fmt.Printf("\nNew clipboard content detected:\nType: %s\n", clip.Type)
		
		// Print available pasteboard types and their values for debugging
		if monitor, ok := monitor.(*clipboard.DarwinMonitor); ok {
			types := monitor.GetPasteboardTypes()
			if len(types) > 0 {
				fmt.Println("Available pasteboard types and values:")
				for _, t := range types {
					fmt.Printf("  - %s\n", t)
				}
			} else {
				fmt.Println("No pasteboard types available")
			}
		}
		
		switch clip.Type {
		case "text":
			fmt.Printf("Content: %s\n", string(clip.Content))
		case "image/png", "image/tiff":
			fmt.Printf("Content: [Binary image data, size: %d bytes]\n", len(clip.Content))
		case "file":
			fmt.Printf("File URL: %s\n", string(clip.Content))
		default:
			fmt.Printf("Content: [Binary data, size: %d bytes]\n", len(clip.Content))
		}
		
		if clip.Metadata.SourceApp != "" {
			fmt.Printf("Source App: %s\n", clip.Metadata.SourceApp)
		}
	})

	// Start monitoring
	if err := monitor.Start(); err != nil {
		log.Fatalf("Failed to start monitor: %v", err)
	}

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	// Clean shutdown
	if err := monitor.Stop(); err != nil {
		log.Printf("Error stopping monitor: %v", err)
	}
}
