package power_usage_exporter

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"
)

// Config holds the exporter configuration
type Config struct {
	Addr string
}

// PowerUsageExporter exposes power metrics via HTTP
type PowerUsageExporter struct {
	config *Config
	server *http.Server
	listener net.Listener
}

// New creates a new PowerUsageExporter
func New(config *Config) *PowerUsageExporter {
	if config.Addr == "" {
		config.Addr = ":8080"
	}

	return &PowerUsageExporter{
		config: config,
	}
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
	mux.Handle("/metrics", promhttp.Handler())

	// Add health check endpoint
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