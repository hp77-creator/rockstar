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
	
	var (
		dbPath  = flag.String("db", "", "Database path (default: ~/.clipboard-manager/clipboard.db)")
		fsPath  = flag.String("fs", "", "File storage path (default: ~/.clipboard-manager/files)")
		port    = flag.Int("port", 54321, "HTTP server port")
	)

	flag.Parse()
	
	log.Printf("Starting clipboard manager...")

	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("Failed to get home directory: %v", err)
	}

	baseDir := filepath.Join(homeDir, ".clipboard-manager")
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		log.Fatalf("Failed to create base directory: %v", err)
	}

	if *dbPath == "" {
		*dbPath = filepath.Join(baseDir, "clipboard.db")
	}
	if *fsPath == "" {
		*fsPath = filepath.Join(baseDir, "files")
	}

	store, err := sqlite.New(storage.Config{
		DBPath: *dbPath,
		FSPath: *fsPath,
	})
	if err != nil {
		log.Fatalf("Failed to initialize storage: %v", err)
	}

	monitor := clipboard.NewMonitor()

	clipService := service.New(monitor, store)
	if err := clipService.Start(); err != nil {
		log.Fatalf("Failed to start clipboard service: %v", err)
	}

	log.Printf("Using configuration:")
	log.Printf("- Database: %s", *dbPath)
	log.Printf("- File storage: %s", *fsPath)
	log.Printf("- HTTP server port: %d", *port)

	httpServer, err := server.New(clipService, server.Config{
		Port: *port,
	})
	if err != nil {
		log.Fatalf("Failed to initialize HTTP server: %v", err)
	}

	log.Printf("Starting HTTP server...")
	if err := httpServer.Start(); err != nil {
		log.Fatalf("Failed to start HTTP server: %v", err)
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down...")

	if err := httpServer.Stop(); err != nil {
		log.Printf("Error stopping HTTP server: %v", err)
	}

	if err := clipService.Stop(); err != nil {
		log.Printf("Error stopping service: %v", err)
	}
}
