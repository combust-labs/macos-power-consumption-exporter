# macOS Power Usage Prometheus Exporter

![Go](https://img.shields.io/badge/Go-1.26+-00ADD8?style=flat&logo=go)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

This program exports the power usage of your macOS device as Prometheus metrics.

## Features

- Exports CPU, GPU, ANE (Apple Neural Engine), and combined power usage
- Prometheus metrics with hostname label
- Automatic reader restart on failure
- Graceful shutdown handling
- Health check endpoint

## Prerequisites

- Go 1.26 or later
- macOS (required for `powermetrics` command)
- `sudo` permissions (required for `powermetrics`)

> **Note:** This program cannot run in a container. The `powermetrics` command is a macOS-specific tool that requires direct hardware access to CPU, GPU, and ANE power sensors. It must run directly on a Mac.

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/combust-labs/macos-power-consumption-exporter.git
cd macos-power-consumption-exporter

# Build
make build

# Or install dependencies and build
make install
make build
```

### Pre-built Binaries

Download the latest release from the [Releases](https://github.com/combust-labs/macos-power-consumption-exporter/releases) page.

## Usage

### Basic Usage

```bash
sudo ./macos-power-consumption-exporter
```

The exporter will start on `http://localhost:8080` by default.

### Custom Address

```bash
sudo ./macos-power-consumption-exporter -addr :9090
```

### Command-line Options

| Flag | Default | Description |
|------|---------|-------------|
| `-addr` | `:8080` | HTTP server address |
| `-log-level` | `info` | Log level (debug, info, warn, error) |

### Makefile Targets

```bash
make build    # Build the binary
make test     # Run tests with coverage
make run      # Build and run (requires sudo)
make clean    # Clean build artifacts
```

## Prometheus Configuration

Add a scrape configuration to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'macos-power-usage'
    static_configs:
      - targets: ['localhost:8080']
```

## Exported Metrics

| Metric | Type | Description | Labels |
|--------|------|-------------|--------|
| `power_usage_reader_cpu_power` | Gauge | CPU power in milliwatts | hostname |
| `power_usage_reader_gpu_power` | Gauge | GPU power in milliwatts | hostname |
| `power_usage_ane_power` | Gauge | Apple Neural Engine power in milliwatts | hostname |
| `power_usage_combined_power` | Gauge | Combined power (CPU + GPU + ANE) in milliwatts | hostname |
| `power_usage_reader_restart_count` | Counter | Number of reader restarts | hostname |

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/metrics` | Prometheus metrics endpoint |
| `/health` | Health check endpoint |

## Architecture

This program contains two main components:

1. **Power Usage Reader** - Reads power metrics from the operating system using `powermetrics` command
2. **Power Usage Exporter** - HTTP server that exposes metrics to Prometheus

### Data Flow

```
powermetrics → Parser → Prometheus Metrics → HTTP Server → Prometheus
```

## Testing

```bash
# Run unit tests
go test ./...

# Run tests with coverage
make test

# Run specific test
go test -v ./internal/power_usage_reader/...
```

## Troubleshooting

### Permission Denied

The `powermetrics` command requires sudo permissions. Make sure to run the exporter with sudo:

```bash
sudo ./macos-power-consumption-exporter
```

### Port Already in Use

If port 8080 is already in use, specify a different port:

```bash
sudo ./macos-power-consumption-exporter -addr :8081
```

### No Metrics Showing

Ensure `powermetrics` is available on your system:

```bash
sudo powermetrics --help
```

### Can I Run This in a Container?

**No.** This program cannot run in Docker, Kubernetes, or any container environment because:

- `powermetrics` is a macOS-specific command that requires direct hardware access
- It accesses CPU, GPU, and ANE power sensors that are not available in containers
- The program must run directly on a Mac with sudo privileges

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.