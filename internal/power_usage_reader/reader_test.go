package power_usage_reader

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPowerMetricsParser(t *testing.T) {
	parser := NewPowerMetricsParser()

	tests := []struct {
		name     string
		line     string
		expected struct {
			metricType string
			value      float64
			found      bool
		}
	}{
		{
			name: "parse CPU power",
			line: "CPU Power: 1996 mW",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"cpu", 1996, true},
		},
		{
			name: "parse GPU power",
			line: "GPU Power: 324 mW",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"gpu", 324, true},
		},
		{
			name: "parse ANE power",
			line: "ANE Power: 0 mW",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"ane", 0, true},
		},
		{
			name: "parse combined power",
			line: "Combined Power (CPU + GPU + ANE): 2320 mW",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"combined", 2320, true},
		},
		{
			name: "parse unknown line",
			line: "Some other output",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"", 0, false},
		},
		{
			name: "parse empty line",
			line: "",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"", 0, false},
		},
		{
			name: "parse high power value",
			line: "CPU Power: 45000 mW",
			expected: struct {
				metricType string
				value      float64
				found      bool
			}{"cpu", 45000, true},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			metricType, value, found := parser.Parse(tt.line)
			assert.Equal(t, tt.expected.found, found)
			if found {
				assert.Equal(t, tt.expected.metricType, metricType)
				assert.Equal(t, tt.expected.value, value)
			}
		})
	}
}

func TestParsePowerLine(t *testing.T) {
	tests := []struct {
		name      string
		line      string
		expected  float64
		expectOk  bool
	}{
		{
			name:     "valid CPU power line",
			line:     "CPU Power: 1996 mW",
			expected: 1996,
			expectOk: true,
		},
		{
			name:     "valid GPU power line",
			line:     "GPU Power: 324 mW",
			expected: 324,
			expectOk: true,
		},
		{
			name:     "zero power",
			line:     "ANE Power: 0 mW",
			expected: 0,
			expectOk: true,
		},
		{
			name:     "invalid format - missing colon",
			line:     "CPU Power 1996 mW",
			expected: 0,
			expectOk: false,
		},
		{
			name:     "valid format without mW suffix",
			line:     "CPU Power: 1996",
			expected: 1996,
			expectOk: true,
		},
		{
			name:     "empty line",
			line:     "",
			expected: 0,
			expectOk: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			value, ok := ParsePowerLine(tt.line)
			assert.Equal(t, tt.expectOk, ok)
			if ok {
				assert.Equal(t, tt.expected, value)
			}
		})
	}
}

func TestIsValidPowerValue(t *testing.T) {
	tests := []struct {
		name     string
		value    float64
		expected bool
	}{
		{"zero value", 0, true},
		{"normal value", 5000, true},
		{"high value", 50000, true},
		{"max reasonable value", 100000, true},
		{"above max", 100001, false},
		{"negative value", -1, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsValidPowerValue(tt.value)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestContainsEmptyValues(t *testing.T) {
	tests := []struct {
		name     string
		metrics  PowerMetrics
		expected bool
	}{
		{
			name:     "all zeros",
			metrics:  PowerMetrics{CPUPower: 0, GPUPower: 0, ANEPower: 0, CombinedPower: 0},
			expected: true,
		},
		{
			name:     "all non-zero",
			metrics:  PowerMetrics{CPUPower: 1000, GPUPower: 500, ANEPower: 100, CombinedPower: 1600},
			expected: false,
		},
		{
			name:     "partial zeros",
			metrics:  PowerMetrics{CPUPower: 1000, GPUPower: 0, ANEPower: 0, CombinedPower: 1000},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ContainsEmptyValues(tt.metrics)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSanitizeMetrics(t *testing.T) {
	t.Run("empty metrics returns as-is", func(t *testing.T) {
		empty := PowerMetrics{CPUPower: 0, GPUPower: 0, ANEPower: 0, CombinedPower: 0}
		result := SanitizeMetrics(empty)
		assert.Equal(t, empty, result)
	})

	t.Run("valid metrics returns as-is", func(t *testing.T) {
		valid := PowerMetrics{CPUPower: 1000, GPUPower: 500, ANEPower: 100, CombinedPower: 1600}
		result := SanitizeMetrics(valid)
		assert.Equal(t, valid, result)
	})
}

func TestNewPowerMetricsParser(t *testing.T) {
	parser := NewPowerMetricsParser()
	require.NotNil(t, parser)
	require.NotNil(t, parser.cpuPowerRE)
	require.NotNil(t, parser.gpuPowerRE)
	require.NotNil(t, parser.anePowerRE)
	require.NotNil(t, parser.combinedPowerRE)
}

func TestPowerUsageReader(t *testing.T) {
	t.Run("creates reader with hostname", func(t *testing.T) {
		reader, err := New()
		require.NoError(t, err)
		require.NotNil(t, reader)
		require.NotEmpty(t, reader.hostname)
	})

	t.Run("initializes parser", func(t *testing.T) {
		reader, err := New()
		require.NoError(t, err)
		require.NotNil(t, reader.parser)
	})

	t.Run("initializes stop channel", func(t *testing.T) {
		reader, err := New()
		require.NoError(t, err)
		require.NotNil(t, reader.stopCh)
	})

	t.Run("initializes with zero metrics", func(t *testing.T) {
		reader, err := New()
		require.NoError(t, err)
		metrics := reader.GetLastMetrics()
		assert.Equal(t, float64(0), metrics.CPUPower)
		assert.Equal(t, float64(0), metrics.GPUPower)
		assert.Equal(t, float64(0), metrics.ANEPower)
		assert.Equal(t, float64(0), metrics.CombinedPower)
	})
}

func TestPowerMetricsToString(t *testing.T) {
	reader, err := New()
	require.NoError(t, err)

	metrics := PowerMetrics{
		CPUPower:      1996,
		GPUPower:      324,
		ANEPower:      0,
		CombinedPower: 2320,
	}

	result := reader.PowerMetricsToString(metrics)
	assert.Contains(t, result, "1996")
	assert.Contains(t, result, "324")
	assert.Contains(t, result, "0")
	assert.Contains(t, result, "2320")
}