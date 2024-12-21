package server

import (
	"clipboard-manager/internal/service"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Server struct {
	clipService *service.ClipboardService
	srv         *http.Server
	config      Config
	pidFile     *pidFile
	hub         *Hub
}

type Config struct {
	Port int
}

func New(clipService *service.ClipboardService, config Config) (*Server, error) {
	pidFile, err := newPIDFile()
	if err != nil {
		return nil, fmt.Errorf("failed to create PID file manager: %w", err)
	}

	hub := newHub()
	go hub.run()

	// Create server instance
	server := &Server{
		clipService: clipService,
		config:      config,
		pidFile:     pidFile,
		hub:         hub,
	}

	// Register the hub as a clipboard change handler
	clipService.RegisterHandler(hub)

	return server, nil
}

func (s *Server) Start() error {
	// Check for existing process
	if existingPID, err := s.pidFile.read(); err != nil {
		return fmt.Errorf("failed to read PID file: %w", err)
	} else if existingPID != 0 {
		if isRunning(existingPID) {
			log.Printf("Found existing clipboard manager process (PID: %d), attempting to terminate", existingPID)
			if err := killProcess(existingPID); err != nil {
				return fmt.Errorf("failed to terminate existing process: %w", err)
			}
			// Give the process time to cleanup
			time.Sleep(500 * time.Millisecond)
		}
		// Clean up stale PID file
		if err := s.pidFile.remove(); err != nil {
			return fmt.Errorf("failed to remove stale PID file: %w", err)
		}
	}

	// Write current PID
	if err := s.pidFile.write(); err != nil {
		return fmt.Errorf("failed to write PID file: %w", err)
	}

	r := chi.NewRouter()

	// Middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(10 * time.Second))

	// Routes
	r.Get("/status", s.handleStatus)
	r.Get("/ws", s.serveWs) // WebSocket endpoint
	r.Route("/api", func(r chi.Router) {
		r.Get("/clips", s.handleGetClips)
		r.Get("/clips/{index}", s.handleGetClip)
		r.Post("/clips/{index}/paste", s.handlePasteClip)
	})

	// Try different addresses if one fails
	addresses := []string{
		fmt.Sprintf("localhost:%d", s.config.Port),
		fmt.Sprintf("127.0.0.1:%d", s.config.Port),
	}

	var lastErr error
	for _, addr := range addresses {
		s.srv = &http.Server{
			Addr:    addr,
			Handler: r,
		}

		log.Printf("Attempting to start HTTP server on %s", addr)
		
		// Create a channel to signal server start
		serverErr := make(chan error, 1)
		
		go func() {
			if err := s.srv.ListenAndServe(); err != http.ErrServerClosed {
				serverErr <- fmt.Errorf("http server error on %s: %w", addr, err)
			}
		}()

		// Wait a moment to see if the server starts successfully
		select {
		case err := <-serverErr:
			lastErr = err
			log.Printf("Failed to start server on %s: %v", addr, err)
			continue
		case <-time.After(100 * time.Millisecond):
			log.Printf("Server started successfully on %s", addr)
			return nil
		}
	}

	return fmt.Errorf("failed to start server on any address: %v", lastErr)
}

func (s *Server) Stop() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := s.srv.Shutdown(ctx); err != nil {
		return fmt.Errorf("error shutting down server: %w", err)
	}

	// Clean up PID file
	if err := s.pidFile.remove(); err != nil {
		log.Printf("Warning: failed to remove PID file: %v", err)
	}

	return nil
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	log.Printf("Status check from %s", r.RemoteAddr)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"time":   time.Now().Format(time.RFC3339),
		"addr":   s.srv.Addr,
	})
}

func (s *Server) handleGetClips(w http.ResponseWriter, r *http.Request) {
	// Get limit and offset from query params
	limit := 10 // default
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	clips, err := s.clipService.GetClips(r.Context(), limit, offset)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(clips)
}

func (s *Server) handleGetClip(w http.ResponseWriter, r *http.Request) {
	index, err := strconv.Atoi(chi.URLParam(r, "index"))
	if err != nil {
		http.Error(w, "invalid index", http.StatusBadRequest)
		return
	}

	clip, err := s.clipService.GetClipByIndex(r.Context(), index)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	json.NewEncoder(w).Encode(clip)
}

func (s *Server) handlePasteClip(w http.ResponseWriter, r *http.Request) {
	index, err := strconv.Atoi(chi.URLParam(r, "index"))
	if err != nil {
		log.Printf("Invalid index parameter: %v", err)
		http.Error(w, "invalid index", http.StatusBadRequest)
		return
	}

	log.Printf("Handling paste request for index: %d", index)
	
	if err := s.clipService.PasteByIndex(r.Context(), index); err != nil {
		log.Printf("Error pasting clip at index %d: %v", index, err)
		
		// Create a detailed error response
		errorResponse := map[string]string{
			"error": err.Error(),
			"detail": fmt.Sprintf("Failed to paste clip at index %d", index),
		}
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(errorResponse)
		return
	}

	log.Printf("Successfully pasted clip at index %d", index)
	w.WriteHeader(http.StatusOK)
}
