package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	startedAt     = time.Now()
	requestsTotal atomic.Uint64
	memoryMu      sync.Mutex
	memoryHolds   [][]byte
)

func main() {
	addr := getenv("TODO_HTTP_ADDR", "127.0.0.1:18080")
	env := getenv("TODO_ENV", "dev")
	pidFile := getenv("TODO_PID_FILE", "")

	if pidFile != "" {
		if err := os.WriteFile(pidFile, []byte(fmt.Sprintf("%d\n", os.Getpid())), 0644); err != nil {
			log.Fatalf("write pid file failed: %v", err)
		}
		defer func() {
			if err := os.Remove(pidFile); err != nil && !os.IsNotExist(err) {
				log.Printf("remove pid file failed: %v", err)
			}
		}()
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", withLog(indexHandler))
	mux.HandleFunc("/healthz", withLog(healthHandler(env)))
	mux.HandleFunc("/work", withLog(workHandler))
	mux.HandleFunc("/memory", withLog(memoryHandler))
	mux.HandleFunc("/metrics-lite", withLog(metricsHandler))

	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Printf("todo-process-demo starting pid=%d env=%s addr=%s", os.Getpid(), env, addr)
		errCh <- server.ListenAndServe()
	}()

	stopCh := make(chan os.Signal, 1)
	signal.Notify(stopCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-stopCh:
		log.Printf("received signal=%s, shutting down", sig)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			log.Printf("graceful shutdown failed: %v", err)
			os.Exit(1)
		}
		log.Println("shutdown complete")
	case err := <-errCh:
		if err != nil && err != http.ErrServerClosed {
			log.Printf("server error: %v", err)
			os.Exit(1)
		}
	}
}

func indexHandler(w http.ResponseWriter, _ *http.Request) {
	writeText(w, http.StatusOK, "todo-process-demo\n\nGET /healthz\nGET /work?ms=500\nGET /memory?mb=16&hold=true\nGET /memory?clear=true\nGET /metrics-lite\n")
}

func healthHandler(env string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		hostname, _ := os.Hostname()
		writeJSON(w, http.StatusOK, map[string]any{
			"status":   "ok",
			"service":  "todo-process-demo",
			"env":      env,
			"pid":      os.Getpid(),
			"hostname": hostname,
			"uptime":   time.Since(startedAt).String(),
			"time":     time.Now().Format(time.RFC3339),
		})
	}
}

func workHandler(w http.ResponseWriter, r *http.Request) {
	ms := parseInt(r.URL.Query().Get("ms"), 300)
	if ms < 1 {
		ms = 1
	}
	if ms > 5000 {
		ms = 5000
	}

	deadline := time.Now().Add(time.Duration(ms) * time.Millisecond)
	var n uint64
	for time.Now().Before(deadline) {
		n++
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"worked_ms": ms,
		"loops":     n,
	})
}

func memoryHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("clear") == "true" {
		memoryMu.Lock()
		memoryHolds = nil
		memoryMu.Unlock()
		runtime.GC()
		writeJSON(w, http.StatusOK, map[string]any{"cleared": true})
		return
	}

	mb := parseInt(r.URL.Query().Get("mb"), 8)
	if mb < 1 {
		mb = 1
	}
	if mb > 64 {
		mb = 64
	}

	buf := make([]byte, mb*1024*1024)
	for i := range buf {
		buf[i] = byte(i)
	}

	held := r.URL.Query().Get("hold") == "true"
	if held {
		memoryMu.Lock()
		memoryHolds = append(memoryHolds, buf)
		memoryMu.Unlock()
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"allocated_mb": mb,
		"held":         held,
	})
}

func metricsHandler(w http.ResponseWriter, _ *http.Request) {
	uptime := int64(time.Since(startedAt).Seconds())
	writeText(w, http.StatusOK, fmt.Sprintf("todo_process_requests_total %d\ntodo_process_uptime_seconds %d\n", requestsTotal.Load(), uptime))
}

func withLog(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		requestsTotal.Add(1)
		next(w, r)
		log.Printf("method=%s path=%s remote=%s duration=%s", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start))
	}
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func parseInt(value string, fallback int) int {
	if value == "" {
		return fallback
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return n
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("write json failed: %v", err)
	}
}

func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	if _, err := w.Write([]byte(body)); err != nil {
		log.Printf("write text failed: %v", err)
	}
}
