package examples

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/service"
	"clipboard-manager/internal/storage"
	"clipboard-manager/internal/storage/sqlite"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

func RunClipboardHistoryTest() {
	// 1. Set up storage in a temporary directory
	tempDir, err := os.MkdirTemp("", "clipboard-test-*")
	if err != nil {
		log.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	store, err := sqlite.New(storage.Config{
		DBPath: filepath.Join(tempDir, "clipboard.db"),
		FSPath: filepath.Join(tempDir, "files"),
	})
	if err != nil {
		log.Fatal(err)
	}

	// 2. Create clipboard service
	monitor := clipboard.NewMonitor()
	clipService := service.New(monitor, store)

	// 3. Start monitoring
	if err := clipService.Start(); err != nil {
		log.Fatal(err)
	}
	defer clipService.Stop()

	// Context for operations
	ctx := context.Background()

	fmt.Println("Starting clipboard history test...")
	fmt.Println("1. Copy some text to your clipboard")
	time.Sleep(3 * time.Second)

	// Debug: List clips after first copy
	clips, err := store.List(ctx, storage.ListFilter{Limit: 10})
	if err != nil {
		log.Printf("Error listing clips: %v", err)
	} else {
		fmt.Printf("Found %d clips after first copy\n", len(clips))
		for i, clip := range clips {
			fmt.Printf("Clip %d: Type=%s, Content=%s\n", i, clip.Type, string(clip.Content))
		}
	}

	fmt.Println("\n2. Copy different text to your clipboard")
	time.Sleep(3 * time.Second)

	// Debug: List clips after second copy
	clips, err = store.List(ctx, storage.ListFilter{Limit: 10})
	if err != nil {
		log.Printf("Error listing clips: %v", err)
	} else {
		fmt.Printf("Found %d clips after second copy\n", len(clips))
		for i, clip := range clips {
			fmt.Printf("Clip %d: Type=%s, Content=%s\n", i, clip.Type, string(clip.Content))
		}
	}

	fmt.Println("\n3. Getting second most recent clip...")
	if err := clipService.PasteByIndex(ctx, 1); err != nil {
		fmt.Printf("Error getting second clip: %v\n", err)
	} else {
		fmt.Println("Successfully set clipboard to second most recent clip")
		fmt.Println("Check if your clipboard contains the first text you copied")
	}

	time.Sleep(2 * time.Second)

	fmt.Println("4. Getting most recent clip...")
	if err := clipService.PasteByIndex(ctx, 0); err != nil {
		fmt.Printf("Error getting most recent clip: %v\n", err)
	} else {
		fmt.Println("Successfully set clipboard to most recent clip")
		fmt.Println("Check if your clipboard contains the second text you copied")
	}

	fmt.Println("\nTest completed!")
}
