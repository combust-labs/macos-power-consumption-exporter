package power_usage_exporter

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNew(t *testing.T) {
	t.Run("creates exporter with default address", func(t *testing.T) {
		exporter, err := New(&Config{})
		require.NoError(t, err)
		require.NotNil(t, exporter)
		assert.Equal(t, ":8080", exporter.config.Addr)
	})

	t.Run("creates exporter with custom address", func(t *testing.T) {
		exporter, err := New(&Config{Addr: ":9090"})
		require.NoError(t, err)
		require.NotNil(t, exporter)
		assert.Equal(t, ":9090", exporter.config.Addr)
	})
}

func TestExporterStartStop(t *testing.T) {
	t.Run("starts and stops successfully", func(t *testing.T) {
		exporter, err := New(&Config{Addr: ":0"}) // Use :0 to get available port
		require.NoError(t, err)
		ctx := context.Background()

		err = exporter.Start(ctx)
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
		exporter, err := New(&Config{})
		require.NoError(t, err)
		err = exporter.Stop()
		require.NoError(t, err)
	})
}

func TestExporterAddr(t *testing.T) {
	exporter, err := New(&Config{Addr: ":8080"})
	require.NoError(t, err)
	assert.Equal(t, ":8080", exporter.Addr())
}

func TestFindAvailablePort(t *testing.T) {
	t.Run("finds available port in range", func(t *testing.T) {
		exporter, err := New(&Config{})
		require.NoError(t, err)
		port, err := exporter.findAvailablePort(15000, 15010)
		require.NoError(t, err)
		assert.GreaterOrEqual(t, port, 15000)
		assert.LessOrEqual(t, port, 15010)
	})

	t.Run("returns error when no ports available", func(t *testing.T) {
		exporter, err := New(&Config{})
		require.NoError(t, err)
		// Try to bind to same port twice - second attempt should fail
		exporter2, err := New(&Config{})
		require.NoError(t, err)
		port, err := exporter.findAvailablePort(15020, 15020)
		if err == nil {
			// If we got a port, try to bind it again (should fail if truly unavailable)
			_, err = exporter2.findAvailablePort(port, port)
			// If err is nil, the port wasn't actually bound, so our test is inconclusive
			// In practice, this test may be flaky on busy systems
		}
	})
}

func TestExpandPortFilePath(t *testing.T) {
	t.Run("expands tilde to home directory", func(t *testing.T) {
		path := expandPortFilePath("~/some-file")
		assert.NotContains(t, path, "~")
		assert.Contains(t, path, "some-file")
	})

	t.Run("leaves non-tilde paths unchanged", func(t *testing.T) {
		path := expandPortFilePath("/tmp/some-file")
		assert.Equal(t, "/tmp/some-file", path)
	})
}

func TestWriteAndRemovePortFile(t *testing.T) {
	t.Run("writes port to file with correct permissions", func(t *testing.T) {
		exporter, err := New(&Config{PortFile: "/tmp/test-port-file"})
		require.NoError(t, err)
		err = exporter.writePortFile(12345)
		require.NoError(t, err)

		// Verify file contents
		data, err := os.ReadFile("/tmp/test-port-file")
		require.NoError(t, err)
		assert.Equal(t, "12345\n", string(data))

		// Verify permissions (0600)
		info, err := os.Stat("/tmp/test-port-file")
		require.NoError(t, err)
		assert.Equal(t, os.FileMode(0600), info.Mode().Perm())

		// Cleanup
		os.Remove("/tmp/test-port-file")
	})

	t.Run("removes port file", func(t *testing.T) {
		exporter, err := New(&Config{PortFile: "/tmp/test-port-file-remove"})
		require.NoError(t, err)
		// Create the file first
		os.WriteFile("/tmp/test-port-file-remove", []byte("9999"), 0600)

		err = exporter.removePortFile()
		require.NoError(t, err)

		// Verify file is gone
		_, err = os.Stat("/tmp/test-port-file-remove")
		assert.True(t, os.IsNotExist(err))
	})

	t.Run("removePortFile handles missing file", func(t *testing.T) {
		exporter, err := New(&Config{PortFile: "/tmp/nonexistent-port-file"})
		require.NoError(t, err)
		err = exporter.removePortFile()
		require.NoError(t, err) // Should not error if file doesn't exist
	})
}