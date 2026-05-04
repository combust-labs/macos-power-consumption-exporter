package power_usage_exporter

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"
)

// Config holds the exporter configuration
type Config struct {
	Addr           string
	AuthHeaderFile string
	PortFile       string
	PortRangeStart int
	PortRangeEnd   int
}

// PowerUsageExporter exposes power metrics via HTTP
type PowerUsageExporter struct {
	config    *Config
	server    *http.Server
	listener  net.Listener
	authToken string
	portFile  string
}

// New creates a new PowerUsageExporter
func New(config *Config) (*PowerUsageExporter, error) {
	if config.Addr == "" {
		config.Addr = ":8080"
	}

	exporter := &PowerUsageExporter{
		config: config,
	}

	// Expand tilde in port file path
	if config.PortFile != "" {
		exporter.portFile = expandPortFilePath(config.PortFile)
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

	// Create listener (handle :0 for ephemeral port)
	var ln net.Listener
	var err error

	if e.config.Addr == ":0" {
		port, err := e.findAvailablePort(e.config.PortRangeStart, e.config.PortRangeEnd)
		if err != nil {
			return fmt.Errorf("failed to find available port: %w", err)
		}
		ln, err = net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err != nil {
			return fmt.Errorf("failed to create listener on ephemeral port: %w", err)
		}
		log.Info().Int("port", port).Msg("bound to ephemeral port")

		// Write port to file
		if e.portFile != "" {
			if err := e.writePortFile(port); err != nil {
				ln.Close()
				return fmt.Errorf("failed to write port file: %w", err)
			}
		}
	} else {
		ln, err = net.Listen("tcp", e.config.Addr)
		if err != nil {
			return fmt.Errorf("failed to create listener: %w", err)
		}
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

	// Clean up port file if it was created
	if e.portFile != "" {
		if err := e.removePortFile(); err != nil {
			log.Warn().Err(err).Msg("failed to remove port file")
		}
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

// findAvailablePort searches for an available port in the given range
func (e *PowerUsageExporter) findAvailablePort(start, end int) (int, error) {
	for port := start; port <= end; port++ {
		ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err != nil {
			// Port is in use, try next
			continue
		}
		ln.Close() // We just need to verify it's available
		return port, nil
	}
	return 0, fmt.Errorf("no available ports in range %d-%d", start, end)
}

// expandPortFilePath expands ~ to the user's home directory
func expandPortFilePath(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}
	return path
}

// writePortFile writes the port number to the port file
func (e *PowerUsageExporter) writePortFile(port int) error {
	log.Info().Str("port-file", e.portFile).Int("port", port).Msg("writing port to file")
	if err := os.WriteFile(e.portFile, []byte(fmt.Sprintf("%d\n", port)), 0600); err != nil {
		return fmt.Errorf("failed to write port file: %w", err)
	}
	return nil
}

// removePortFile removes the port file
func (e *PowerUsageExporter) removePortFile() error {
	log.Info().Str("port-file", e.portFile).Msg("removing port file")
	if err := os.Remove(e.portFile); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove port file: %w", err)
	}
	return nil
}