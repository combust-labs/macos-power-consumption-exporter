package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/combust-labs/macos-power-consumption-exporter/internal/power_usage_exporter"
	"github.com/combust-labs/macos-power-consumption-exporter/internal/power_usage_reader"
	"github.com/combust-labs/macos-power-consumption-exporter/pkg/metrics"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

var (
	// Version is set at build time
	Version = "dev"

	// Commit is set at build time
	Commit = "unknown"

	// Default port file path
	defaultPortFile = "$HOME/.macos-power-consumption-exporter-port-file"
)

func getEnvOrDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func main() {
	// Parse flags
	exporterAddr := flag.String("addr", ":8080", "HTTP server address")
	logLevel := flag.String("log-level", "info", "Log level (debug, info, warn, error)")
	authHeaderFile := flag.String("auth-header-file", "", "Path to file containing auth token (enables auth on /metrics)")
	portFile := flag.String("port-file", getEnvOrDefault("EXPORTER_PORT_FILE", defaultPortFile), "Path to file for ephemeral port (use with -addr :0)")
	portRangeStart := flag.Int("port-range-start", 8000, "Start of port range for ephemeral binding")
	portRangeEnd := flag.Int("port-range-end", 9000, "End of port range for ephemeral binding")
	flag.Parse()

	// Set up logging
	configureLogging(*logLevel)

	log.Info().
		Str("version", Version).
		Str("commit", Commit).
		Msg("starting macos-power-consumption-exporter")

	// Get hostname for metrics
	hostname, err := os.Hostname()
	if err != nil {
		log.Fatal().Err(err).Msg("failed to get hostname")
	}

	// Create context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up signal handling
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigCh
		log.Info().Str("signal", sig.String()).Msg("received shutdown signal")
		cancel()
	}()

	// Create and start the exporter
	exporter, err := power_usage_exporter.New(&power_usage_exporter.Config{
		Addr:           *exporterAddr,
		AuthHeaderFile: *authHeaderFile,
		PortFile:       *portFile,
		PortRangeStart: *portRangeStart,
		PortRangeEnd:   *portRangeEnd,
	})
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create exporter")
	}

	if err := exporter.Start(ctx); err != nil {
		log.Fatal().Err(err).Msg("failed to start exporter")
	}

	log.Info().Str("addr", exporter.Addr()).Msg("exporter started")

	// Create and start the reader with automatic restart
	reader, err := power_usage_reader.New()
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create reader")
	}

	// Start reader with restart logic
	runReaderWithRestart(ctx, reader, hostname)

	log.Info().Msg("shutting down")

	// Stop exporter
	if err := exporter.Stop(); err != nil {
		log.Error().Err(err).Msg("error stopping exporter")
	}

	log.Info().Msg("shutdown complete")
}

func runReaderWithRestart(ctx context.Context, reader *power_usage_reader.PowerUsageReader, hostname string) {
	backoff := time.Second
	maxBackoff := 30 * time.Second

	for {
		select {
		case <-ctx.Done():
			reader.Stop()
			return
		default:
		}

		// Start the reader
		if err := reader.Start(ctx); err != nil {
			log.Error().Err(err).Msg("failed to start reader, will retry")
			incrementRestartCounter(hostname)
			backoff = sleepWithContext(ctx, backoff)
			backoff = minDuration(backoff*2, maxBackoff)
			continue
		}

		// Reader started successfully, reset backoff
		backoff = time.Second

		// Wait for reader to stop or context to cancel
		<-ctx.Done()
		reader.Stop()

		// Check if we should restart
		select {
		case <-ctx.Done():
			return
		default:
		}

		log.Info().Msg("reader stopped, restarting")
		incrementRestartCounter(hostname)
	}
}

func incrementRestartCounter(hostname string) {
	metrics.ReaderRestartCount.WithLabelValues(hostname).Inc()
	log.Info().Msg("reader restart counter incremented")
}

func sleepWithContext(ctx context.Context, duration time.Duration) time.Duration {
	select {
	case <-ctx.Done():
		return duration
	case <-time.After(duration):
		return duration
	}
}

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}

func configureLogging(level string) {
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	lvl, err := zerolog.ParseLevel(level)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid log level: %s, defaulting to info\n", level)
		lvl = zerolog.InfoLevel
	}

	zerolog.SetGlobalLevel(lvl)

	// Console output with colors
	log.Logger = log.Output(zerolog.ConsoleWriter{
		Out:     os.Stderr,
		NoColor: os.Getenv("NO_COLOR") != "",
	})
}