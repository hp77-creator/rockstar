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
}

type Config struct {
	Port int
}

func New(clipService *service.ClipboardService, config Config) *Server {
	return &Server{
		clipService: clipService,
		config:      config,
	}
}

func (s *Server) Start() error {
	r := chi.NewRouter()

	// Middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(10 * time.Second))

	// Routes
	r.Get("/status", s.handleStatus)
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
		http.Error(w, "invalid index", http.StatusBadRequest)
		return
	}

	if err := s.clipService.PasteByIndex(r.Context(), index); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}
