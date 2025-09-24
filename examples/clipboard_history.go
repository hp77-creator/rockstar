package examples

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/service"
	"clipboard-manager/internal/storage"
	"clipboard-manager/internal/storage/sqlite"
	"clipboard-manager/pkg/types"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

func RunClipboardHistoryTest() {
	tempDir, err := os.MkdirTemp("", "clipboard-test-*")
	if err != nil {
		log.Fatal(err)
	}
	defer func(path string) {
		err := os.RemoveAll(path)
		if err != nil {

		}
	}(tempDir)

	store, err := sqlite.New(storage.Config{
		DBPath: filepath.Join(tempDir, "clipboard.db"),
		FSPath: filepath.Join(tempDir, "files"),
	})
	if err != nil {
		log.Fatal(err)
	}

	monitor := clipboard.NewMonitor()
	clipService := service.New(monitor, store)

	if err := clipService.Start(); err != nil {
		log.Fatal(err)
	}
	defer clipService.Stop()

	ctx := context.Background()

	fmt.Println("Starting clipboard history test...")
	fmt.Println("1. Adding first test clip")
	firstClip := types.Clip{
		Content:   []byte("This is the first test clip"),
		Type:      "text/plain",
		CreatedAt: time.Now(),
	}
	if err := monitor.SetContent(firstClip); err != nil {
		log.Printf("Error setting first clip: %v", err)
	}
	time.Sleep(2 * time.Second)

	clips, err := store.List(ctx, storage.ListFilter{Limit: 10})
	if err != nil {
		log.Printf("Error listing clips: %v", err)
	} else {
		fmt.Printf("Found %d clips after first copy\n", len(clips))
		for i, clip := range clips {
			fmt.Printf("Clip %d: Type=%s, Content=%s\n", i, clip.Type, string(clip.Content))
		}
	}

	fmt.Println("\n2. Adding second test clip")
	secondClip := types.Clip{
		Content:   []byte("This is the second test clip"),
		Type:      "text/plain",
		CreatedAt: time.Now(),
	}
	if err := monitor.SetContent(secondClip); err != nil {
		log.Printf("Error setting second clip: %v", err)
	}
	time.Sleep(2 * time.Second)

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
