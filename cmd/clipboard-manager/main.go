package main

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/service"
	"clipboard-manager/internal/storage"
	"clipboard-manager/internal/storage/sqlite"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func main() {
	// Set up storage paths in user's home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("Failed to get home directory: %v", err)
	}

	baseDir := filepath.Join(homeDir, ".clipboard-manager")
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		log.Fatalf("Failed to create base directory: %v", err)
	}

	// Initialize storage
	store, err := sqlite.New(storage.Config{
		DBPath: filepath.Join(baseDir, "clipboard.db"),
		FSPath: filepath.Join(baseDir, "files"),
	})
	if err != nil {
		log.Fatalf("Failed to initialize storage: %v", err)
	}

	// Initialize monitor
	monitor := clipboard.NewMonitor()

	// Create and start clipboard service
	clipService := service.New(monitor, store)
	if err := clipService.Start(); err != nil {
		log.Fatalf("Failed to start clipboard service: %v", err)
	}

	log.Printf("Clipboard manager started. Data directory: %s", baseDir)
	log.Println("Press Ctrl+C to stop")

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	// Clean shutdown
	log.Println("Shutting down...")
	if err := clipService.Stop(); err != nil {
		log.Printf("Error stopping service: %v", err)
	}
}
