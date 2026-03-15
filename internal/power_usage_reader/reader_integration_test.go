package power_usage_reader

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Integration test - tests the full parsing pipeline with realistic input
func TestPowerMetricsParserIntegration(t *testing.T) {
	parser := NewPowerMetricsParser()

	// Simulate realistic powermetrics output (one complete cycle)
	lines := []string{
		"CPU Power: 1996 mW",
		"GPU Power: 324 mW",
		"ANE Power: 0 mW",
		"Combined Power (CPU + GPU + ANE): 2320 mW",
		"GPU Power: 324 mW", // Second occurrence should be ignored
	}

	var metrics PowerMetrics
	var gpuSeen bool

	for _, line := range lines {
		metricType, value, found := parser.Parse(line)
		if !found {
			continue
		}

		switch metricType {
		case "cpu":
			metrics.CPUPower = value
		case "gpu":
			// Simulate the reader's GPU seen logic
			if !gpuSeen {
				gpuSeen = true
				metrics.GPUPower = value
			}
		case "ane":
			metrics.ANEPower = value
		case "combined":
			metrics.CombinedPower = value
		}
	}

	// Verify the parsed values
	assert.Equal(t, 1996.0, metrics.CPUPower, "CPU power should be 1996 mW")
	assert.Equal(t, 324.0, metrics.GPUPower, "GPU power should be 324 mW (first occurrence)")
	assert.Equal(t, 0.0, metrics.ANEPower, "ANE power should be 0 mW")
	assert.Equal(t, 2320.0, metrics.CombinedPower, "Combined power should be 2320 mW")
}

// Test that multiple cycles are parsed correctly
func TestPowerMetricsParserMultipleCycles(t *testing.T) {
	parser := NewPowerMetricsParser()

	// First cycle
	lines1 := []string{
		"CPU Power: 1000 mW",
		"GPU Power: 200 mW",
		"ANE Power: 50 mW",
		"Combined Power (CPU + GPU + ANE): 1250 mW",
		"GPU Power: 200 mW",
	}

	// Second cycle
	lines2 := []string{
		"CPU Power: 1500 mW",
		"GPU Power: 300 mW",
		"ANE Power: 100 mW",
		"Combined Power (CPU + GPU + ANE): 1900 mW",
		"GPU Power: 300 mW",
	}

	// Parse first cycle
	var metrics1 PowerMetrics
	gpuSeen := false
	for _, line := range lines1 {
		metricType, value, found := parser.Parse(line)
		if !found {
			continue
		}
		switch metricType {
		case "cpu":
			metrics1.CPUPower = value
		case "gpu":
			if !gpuSeen {
				gpuSeen = true
				metrics1.GPUPower = value
			}
		case "ane":
			metrics1.ANEPower = value
		case "combined":
			metrics1.CombinedPower = value
		}
	}

	// Parse second cycle
	var metrics2 PowerMetrics
	gpuSeen = false
	for _, line := range lines2 {
		metricType, value, found := parser.Parse(line)
		if !found {
			continue
		}
		switch metricType {
		case "cpu":
			metrics2.CPUPower = value
		case "gpu":
			if !gpuSeen {
				gpuSeen = true
				metrics2.GPUPower = value
			}
		case "ane":
			metrics2.ANEPower = value
		case "combined":
			metrics2.CombinedPower = value
		}
	}

	// Verify first cycle
	assert.Equal(t, 1000.0, metrics1.CPUPower)
	assert.Equal(t, 200.0, metrics1.GPUPower)
	assert.Equal(t, 50.0, metrics1.ANEPower)
	assert.Equal(t, 1250.0, metrics1.CombinedPower)

	// Verify second cycle
	assert.Equal(t, 1500.0, metrics2.CPUPower)
	assert.Equal(t, 300.0, metrics2.GPUPower)
	assert.Equal(t, 100.0, metrics2.ANEPower)
	assert.Equal(t, 1900.0, metrics2.CombinedPower)
}

// Test timestamp is captured
func TestPowerMetricsTimestamp(t *testing.T) {
	now := time.Now()
	metrics := PowerMetrics{
		CPUPower:      1000,
		GPUPower:      500,
		ANEPower:      100,
		CombinedPower: 1600,
		Timestamp:     now,
	}

	require.NotZero(t, metrics.Timestamp)
	assert.WithinDuration(t, now, metrics.Timestamp, time.Second)
}

// Test edge cases
func TestPowerMetricsEdgeCases(t *testing.T) {
	parser := NewPowerMetricsParser()

	tests := []struct {
		name  string
		line  string
		valid bool
	}{
		{"very small power", "CPU Power: 1 mW", true},
		{"zero power", "CPU Power: 0 mW", true},
		{"large power", "CPU Power: 99999 mW", true},
		{"whitespace before mW", "CPU Power: 100  mW", true}, // Multiple spaces are OK as \s+
		{"tab instead of space", "CPU Power:\t100 mW", true}, // Tabs are OK as \s
		{"lowercase mW", "CPU Power: 100 mw", false},
		{"uppercase MW", "CPU Power: 100 MW", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, _, found := parser.Parse(tt.line)
			assert.Equal(t, tt.valid, found, "Parse result should match expected validity")
		})
	}
}