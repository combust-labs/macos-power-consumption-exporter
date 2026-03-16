package power_usage_exporter

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNew(t *testing.T) {
	t.Run("creates exporter with default address", func(t *testing.T) {
		exporter := New(&Config{})
		require.NotNil(t, exporter)
		assert.Equal(t, ":8080", exporter.config.Addr)
	})

	t.Run("creates exporter with custom address", func(t *testing.T) {
		exporter := New(&Config{Addr: ":9090"})
		require.NotNil(t, exporter)
		assert.Equal(t, ":9090", exporter.config.Addr)
	})
}

func TestExporterStartStop(t *testing.T) {
	t.Run("starts and stops successfully", func(t *testing.T) {
		exporter := New(&Config{Addr: ":0"}) // Use :0 to get available port
		ctx := context.Background()

		err := exporter.Start(ctx)
		require.NoError(t, err)

		// Give server time to start and bind to port
		time.Sleep(200 * time.Millisecond)

		// Get the actual address (the server assigns a port)
		addr := exporter.Addr()
		require.NotEqual(t, ":0", addr, "server should have bound to a real port")

		// Test health endpoint
		resp, err := http.Get("http://" + addr + "/health")
		require.NoError(t, err)
		assert.Equal(t, http.StatusOK, resp.StatusCode)
		resp.Body.Close()

		// Test metrics endpoint
		resp, err = http.Get("http://" + addr + "/metrics")
		require.NoError(t, err)
		assert.Equal(t, http.StatusOK, resp.StatusCode)
		resp.Body.Close()

		// Stop exporter
		err = exporter.Stop()
		require.NoError(t, err)
	})

	t.Run("handles stop when not started", func(t *testing.T) {
		exporter := New(&Config{})
		err := exporter.Stop()
		require.NoError(t, err)
	})
}

func TestExporterAddr(t *testing.T) {
	exporter := New(&Config{Addr: ":8080"})
	assert.Equal(t, ":8080", exporter.Addr())
}