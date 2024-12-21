package main

import (
	"clipboard-manager/internal/clipboard"
	"clipboard-manager/internal/server"
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
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)
	
	// Configuration flags
	var (
		dbPath  = flag.String("db", "", "Database path (default: ~/.clipboard-manager/clipboard.db)")
		fsPath  = flag.String("fs", "", "File storage path (default: ~/.clipboard-manager/files)")
		port    = flag.Int("port", 54321, "HTTP server port")
	)

	flag.Parse()
	
	log.Printf("Starting clipboard manager...")

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

	log.Printf("Using configuration:")
	log.Printf("- Database: %s", *dbPath)
	log.Printf("- File storage: %s", *fsPath)
	log.Printf("- HTTP server port: %d", *port)

	// Initialize HTTP server
	httpServer, err := server.New(clipService, server.Config{
		Port: *port,
	})
	if err != nil {
		log.Fatalf("Failed to initialize HTTP server: %v", err)
	}

	// Start HTTP server
	log.Printf("Starting HTTP server...")
	if err := httpServer.Start(); err != nil {
		log.Fatalf("Failed to start HTTP server: %v", err)
	}

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	// Clean shutdown
	log.Println("Shutting down...")

	// Stop HTTP server first
	if err := httpServer.Stop(); err != nil {
		log.Printf("Error stopping HTTP server: %v", err)
	}

	// Stop clipboard service
	if err := clipService.Stop(); err != nil {
		log.Printf("Error stopping service: %v", err)
	}
}
