// cmd/server/main.go — minimal Go HTTP service
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
)

type Item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

var (
	mu     sync.RWMutex
	items  = []Item{{ID: 1, Name: "Widget A"}, {ID: 2, Name: "Widget B"}}
	nextID = atomic.Int32{}
)

func init() { nextID.Store(3) }

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /items", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		defer mu.RUnlock()
		writeJSON(w, 200, items)
	})

	mux.HandleFunc("POST /items", func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Name string }
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, 400, map[string]string{"error": "bad request"})
			return
		}
		item := Item{ID: int(nextID.Add(1)) - 1, Name: req.Name}
		mu.Lock()
		items = append(items, item)
		mu.Unlock()
		writeJSON(w, 201, item)
	})

	log.Printf("go-service listening on :%s", port)
	if err := http.ListenAndServe(fmt.Sprintf("0.0.0.0:%s", port), mux); err != nil {
		log.Fatal(err)
	}
}
