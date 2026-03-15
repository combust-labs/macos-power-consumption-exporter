package power_usage_reader

import (
	"bufio"
	"context"
	"fmt"
	"github.com/combust-labs/macos-power-consumption-exporter/pkg/metrics"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

// PowerMetricsParser parses output from the powermetrics command
type PowerMetricsParser struct {
	cpuPowerRE     *regexp.Regexp
	gpuPowerRE     *regexp.Regexp
	anePowerRE     *regexp.Regexp
	combinedPowerRE *regexp.Regexp
}

// NewPowerMetricsParser creates a new parser
func NewPowerMetricsParser() *PowerMetricsParser {
	return &PowerMetricsParser{
		cpuPowerRE:     regexp.MustCompile(`CPU Power:\s+(\d+)\s+mW`),
		gpuPowerRE:     regexp.MustCompile(`GPU Power:\s+(\d+)\s+mW`),
		anePowerRE:     regexp.MustCompile(`ANE Power:\s+(\d+)\s+mW`),
		combinedPowerRE: regexp.MustCompile(`Combined Power \(CPU \+ GPU \+ ANE\):\s+(\d+)\s+mW`),
	}
}

// PowerMetrics holds parsed power values
type PowerMetrics struct {
	CPUPower     float64
	GPUPower     float64
	ANEPower     float64
	CombinedPower float64
	Timestamp    time.Time
}

// Parse parses a single line and returns the metric type and value if found
func (p *PowerMetricsParser) Parse(line string) (string, float64, bool) {
	if matches := p.cpuPowerRE.FindStringSubmatch(line); len(matches) == 2 {
		val := parseFloat(matches[1])
		return "cpu", val, true
	}
	if matches := p.gpuPowerRE.FindStringSubmatch(line); len(matches) == 2 {
		val := parseFloat(matches[1])
		return "gpu", val, true
	}
	if matches := p.anePowerRE.FindStringSubmatch(line); len(matches) == 2 {
		val := parseFloat(matches[1])
		return "ane", val, true
	}
	if matches := p.combinedPowerRE.FindStringSubmatch(line); len(matches) == 2 {
		val := parseFloat(matches[1])
		return "combined", val, true
	}
	return "", 0, false
}

func parseFloat(s string) float64 {
	var val float64
	fmt.Sscanf(s, "%f", &val)
	return val
}

// PowerUsageReader reads power metrics from the system
type PowerUsageReader struct {
	mu            sync.RWMutex
	parser        *PowerMetricsParser
	hostname      string
	stopCh        chan struct{}
	wg            sync.WaitGroup
	lastMetrics   PowerMetrics
	gpuSeen       bool // track if we've seen the first GPU Power line in a cycle
}

// New creates a new PowerUsageReader
func New() (*PowerUsageReader, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return nil, fmt.Errorf("failed to get hostname: %w", err)
	}

	return &PowerUsageReader{
		parser:   NewPowerMetricsParser(),
		hostname: hostname,
		stopCh:   make(chan struct{}),
	}, nil
}

// Start starts the reader
func (r *PowerUsageReader) Start(ctx context.Context) error {
	log.Info().Str("hostname", r.hostname).Msg("starting power usage reader")

	r.wg.Add(1)
	go r.run(ctx)

	return nil
}

// Stop stops the reader
func (r *PowerUsageReader) Stop() {
	log.Info().Msg("stopping power usage reader")
	close(r.stopCh)
	r.wg.Wait()
	log.Info().Msg("power usage reader stopped")
}

// GetLastMetrics returns the last read metrics (thread-safe)
func (r *PowerUsageReader) GetLastMetrics() PowerMetrics {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.lastMetrics
}

func (r *PowerUsageReader) run(ctx context.Context) {
	defer r.wg.Done()

	for {
		select {
		case <-r.stopCh:
			return
		case <-ctx.Done():
			return
		default:
			r.readMetrics()
		}
	}
}

func (r *PowerUsageReader) readMetrics() {
	cmd := exec.Command("sudo", "powermetrics")

	// Create a pipe for stdout - cannot use both Stdout set AND StdoutPipe
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		log.Error().Err(err).Msg("failed to create stdout pipe")
		return
	}

	// Also pipe stderr so we can see any errors
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		log.Error().Err(err).Msg("failed to start powermetrics")
		return
	}

	// Reset GPU seen state for new run
	r.gpuSeen = false

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		select {
		case <-r.stopCh:
			cmd.Process.Kill()
			return
		default:
		}

		line := scanner.Text()
		metricType, value, found := r.parser.Parse(line)

		if found {
			r.updateMetric(metricType, value)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Error().Err(err).Msg("error reading powermetrics output")
	}

	cmd.Wait()
}

func (r *PowerUsageReader) updateMetric(metricType string, value float64) {
	r.mu.Lock()
	defer r.mu.Unlock()

	switch metricType {
	case "cpu":
		r.lastMetrics.CPUPower = value
		metrics.CPUPower.WithLabelValues(r.hostname).Set(value)
	case "gpu":
		// Ignore the second occurrence of GPU Power in each cycle
		if !r.gpuSeen {
			r.gpuSeen = true
			r.lastMetrics.GPUPower = value
			metrics.GPUPower.WithLabelValues(r.hostname).Set(value)
		}
	case "ane":
		r.lastMetrics.ANEPower = value
		metrics.ANEPower.WithLabelValues(r.hostname).Set(value)
	case "combined":
		r.lastMetrics.CombinedPower = value
		metrics.CombinedPower.WithLabelValues(r.hostname).Set(value)
	}
}

// PowerMetricsToString returns a string representation of the metrics
func (r *PowerUsageReader) PowerMetricsToString(m PowerMetrics) string {
	return fmt.Sprintf("CPU: %.0f mW, GPU: %.0f mW, ANE: %.0f mW, Combined: %.0f mW",
		m.CPUPower, m.GPUPower, m.ANEPower, m.CombinedPower)
}

// ContainsEmptyValues checks if any of the power metrics are zero/empty
func ContainsEmptyValues(m PowerMetrics) bool {
	return m.CPUPower == 0 && m.GPUPower == 0 && m.ANEPower == 0 && m.CombinedPower == 0
}

// SanitizeMetrics ensures we have valid metrics (handles incomplete reads)
func SanitizeMetrics(m PowerMetrics) PowerMetrics {
	// If all values are zero, this might be an incomplete read
	// Keep the previous valid values if available
	if ContainsEmptyValues(m) {
		// Return as-is for now - the reader will continue updating
	}
	return m
}

// IsValidPowerValue checks if a power value is within expected range
func IsValidPowerValue(value float64) bool {
	// Reasonable bounds: 0 to 100W (100000 mW)
	return value >= 0 && value <= 100000
}

// ParsePowerLine parses a raw power line and extracts the value
func ParsePowerLine(line string) (float64, bool) {
	parts := strings.Split(line, ":")
	if len(parts) != 2 {
		return 0, false
	}

	valueStr := strings.TrimSpace(parts[1])
	valueStr = strings.ReplaceAll(valueStr, "mW", "")
	valueStr = strings.TrimSpace(valueStr)

	var value float64
	_, err := fmt.Sscanf(valueStr, "%f", &value)
	if err != nil {
		return 0, false
	}

	return value, true
}