package main

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/service"
	"clipboard-manager/internal/storage"
	"clipboard-manager/internal/storage/sqlite"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func main() {
	// Configuration flags
	var (
		dbPath  = flag.String("db", "", "Database path (default: ~/.clipboard-manager/clipboard.db)")
		fsPath  = flag.String("fs", "", "File storage path (default: ~/.clipboard-manager/files)")
		verbose = flag.Bool("verbose", false, "Enable verbose logging")
	)

	flag.Parse()

	// Set up storage paths
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("Failed to get home directory: %v", err)
	}

	baseDir := filepath.Join(homeDir, ".clipboard-manager")
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		log.Fatalf("Failed to create base directory: %v", err)
	}

	// Use provided paths or defaults
	if *dbPath == "" {
		*dbPath = filepath.Join(baseDir, "clipboard.db")
	}
	if *fsPath == "" {
		*fsPath = filepath.Join(baseDir, "files")
	}

	// Initialize storage
	store, err := sqlite.New(storage.Config{
		DBPath: *dbPath,
		FSPath: *fsPath,
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

	if *verbose {
		log.Printf("Clipboard manager started")
		log.Printf("Database: %s", *dbPath)
		log.Printf("File storage: %s", *fsPath)
	}

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	// Clean shutdown
	if *verbose {
		log.Println("Shutting down...")
	}
	if err := clipService.Stop(); err != nil {
		log.Printf("Error stopping service: %v", err)
	}
}
