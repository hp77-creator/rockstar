package server

import (
	"clipboard-manager/pkg/types"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins in development
	},
}

// Hub maintains the set of active clients and broadcasts messages to them
type Hub struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

// Client is a middleman between the websocket connection and the hub
type Client struct {
	hub  *Hub
	conn *websocket.Conn
	send chan []byte
}

func newHub() *Hub {
	return &Hub{
		broadcast:  make(chan []byte),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		clients:    make(map[*Client]bool),
	}
}

func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("New client connected. Total clients: %d", len(h.clients))

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
			}
			h.mu.Unlock()
			log.Printf("Client disconnected. Total clients: %d", len(h.clients))

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					close(client.send)
					delete(h.clients, client)
				}
			}
			h.mu.RUnlock()
		}
	}
}

// HandleClipboardChange implements service.ClipboardChangeHandler
func (h *Hub) HandleClipboardChange(clip types.Clip) {
	// Create a notification message
	notification := struct {
		Type    string      `json:"type"`
		Payload types.Clip `json:"payload"`
	}{
		Type:    "clipboard_change",
		Payload: clip,
	}

	// Marshal the notification
	message, err := json.Marshal(notification)
	if err != nil {
		log.Printf("Error marshaling clipboard notification: %v", err)
		return
	}

	h.broadcast <- message
}

// writePump pumps messages from the hub to the websocket connection
func (c *Client) writePump() {
	defer func() {
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			if !ok {
				// The hub closed the channel
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			if err := w.Close(); err != nil {
				return
			}
		}
	}
}

// serveWs handles websocket requests from clients
func (s *Server) serveWs(w http.ResponseWriter, r *http.Request) {
	log.Printf("WebSocket connection attempt from %s", r.RemoteAddr)
	log.Printf("Request headers: %+v", r.Header)

	// Check if it's a websocket upgrade request
	if !websocket.IsWebSocketUpgrade(r) {
		log.Printf("Not a WebSocket upgrade request from %s", r.RemoteAddr)
		http.Error(w, "Expected WebSocket Upgrade", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Error upgrading connection from %s: %v", r.RemoteAddr, err)
		// Check for specific upgrade errors
		if strings.Contains(err.Error(), "websocket: missing client key") {
			log.Printf("Client did not provide Sec-WebSocket-Key header")
		}
		if strings.Contains(err.Error(), "websocket: version != 13") {
			log.Printf("Unsupported WebSocket version")
		}
		return
	}

	log.Printf("WebSocket connection established with %s", r.RemoteAddr)

	client := &Client{
		hub:  s.hub,
		conn: conn,
		send: make(chan []byte, 256),
	}
	client.hub.register <- client

	// Start the write pump in a new goroutine
	go client.writePump()
}
