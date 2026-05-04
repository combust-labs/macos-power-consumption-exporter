package power_usage_exporter

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"
)

// Config holds the exporter configuration
type Config struct {
	Addr           string
	AuthHeaderFile string
}

// PowerUsageExporter exposes power metrics via HTTP
type PowerUsageExporter struct {
	config    *Config
	server    *http.Server
	listener  net.Listener
	authToken string
}

// New creates a new PowerUsageExporter
func New(config *Config) (*PowerUsageExporter, error) {
	if config.Addr == "" {
		config.Addr = ":8080"
	}

	exporter := &PowerUsageExporter{
		config: config,
	}

	// Load auth token if configured
	if config.AuthHeaderFile != "" {
		token, err := os.ReadFile(config.AuthHeaderFile)
		if err != nil {
			return nil, fmt.Errorf("failed to read auth header file: %w", err)
		}
		exporter.authToken = strings.TrimSpace(string(token))
		log.Info().Str("auth-header-file", config.AuthHeaderFile).Msg("auth enabled for /metrics endpoint")
	}

	return exporter, nil
}

// Start starts the HTTP server
func (e *PowerUsageExporter) Start(ctx context.Context) error {
	log.Info().Str("addr", e.config.Addr).Msg("starting power usage exporter")

	// Create listener
	ln, err := net.Listen("tcp", e.config.Addr)
	if err != nil {
		return fmt.Errorf("failed to create listener: %w", err)
	}
	e.listener = ln

	mux := http.NewServeMux()

	// Wrap /metrics with auth if configured
	if e.authToken != "" {
		metricsHandler := promhttp.Handler()
		mux.Handle("/metrics", authMiddleware(metricsHandler, e.authToken))
	} else {
		mux.Handle("/metrics", promhttp.Handler())
	}

	// Add health check endpoint (no auth required)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "OK\n")
	})

	e.server = &http.Server{
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		if err := e.server.Serve(ln); err != nil && err != http.ErrServerClosed {
			log.Error().Err(err).Msg("exporter server error")
		}
	}()

	return nil
}

// Stop stops the HTTP server gracefully
func (e *PowerUsageExporter) Stop() error {
	log.Info().Msg("stopping power usage exporter")

	if e.server == nil {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := e.server.Shutdown(ctx); err != nil {
		log.Error().Err(err).Msg("error shutting down exporter server")
		return err
	}

	log.Info().Msg("power usage exporter stopped")
	return nil
}

// Addr returns the listening address
func (e *PowerUsageExporter) Addr() string {
	if e.listener != nil {
		return e.listener.Addr().String()
	}
	return e.config.Addr
}

// authMiddleware wraps an http.Handler to require Bearer token authentication
func authMiddleware(next http.Handler, token string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		expected := "Bearer " + token
		if authHeader != expected {
			w.WriteHeader(http.StatusUnauthorized)
			fmt.Fprintf(w, "Unauthorized\n")
			return
		}
		next.ServeHTTP(w, r)
	})
}