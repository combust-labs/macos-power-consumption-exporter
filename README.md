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

### DMG Installer (Recommended for macOS)

For a native macOS installation experience, download the DMG installer:

1. Download the latest `.dmg` file from [Releases](https://github.com/combust-labs/macos-power-consumption-exporter/releases)
2. Double-click the DMG to mount it
3. Drag "MacOS Power Consumption Exporter" to the Applications folder
4. Launch the application from Applications

The app runs in the menu bar. On first launch, you may be prompted for administrator privileges (required for `powermetrics`).

#### Building the DMG from Source

```bash
# Clone and build
git clone https://github.com/combust-labs/macos-power-consumption-exporter.git
cd macos-power-consumption-exporter

# Build unsigned DMG (for development/testing)
make dmg-unsigned

# The DMG will be created at: dist/MacOS Power Consumption Exporter.dmg
```

For a signed DMG (for distribution), see the [Signing & Distribution](#signing--distribution) section.

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

## Uninstallation

### Via DMG Installer

If you installed via DMG:

1. Open Finder → Applications
2. Drag "MacOS Power Consumption Exporter" to Trash
3. Run the uninstall script (optional but recommended):

```bash
# Download and run uninstall script
curl -L -o uninstall.sh https://raw.githubusercontent.com/combust-labs/macos-power-consumption-exporter/main/installer/scripts/uninstall.sh
chmod +x uninstall.sh
./uninstall.sh
```

### Via Command Line

If you installed the binary manually:

```bash
# Stop the exporter if running
sudo pkill macos-power-consumption-exporter

# Remove the binary
sudo rm -f /usr/local/bin/macos-power-consumption-exporter
```

### What Gets Removed

The uninstall script removes:
- Application bundle from `/Applications` or `~/Applications`
- Launch agent (`~/Library/LaunchAgents/com.combust.macos-power-consumption-exporter.plist`)
- Log files (`~/Library/Logs/com.combust.macos-power-consumption-exporter/`)
- Cache files (`~/Library/Caches/com.combust.macos-power-consumption-exporter/`)
- Preference files

## Signing & Distribution

For distribution outside the Mac App Store, you can sign and notarize the app:

### Prerequisites

- Apple Developer ID certificate
- App-specific password for notarization

### Build Signed DMG

```bash
# Set your certificate name
export CERTIFICATE="Developer ID Application: Your Name"

# Build signed DMG
make dmg
```

### Full Distribution Build

```bash
# Set all required environment variables
export CERTIFICATE="Developer ID Application: Your Name"
export APPLE_ID="your@email.com"
export APP_PASSWORD="app-specific-password"
export TEAM_ID="YOUR_TEAM_ID"

# Build, sign, notarize, and package
make dist
```

### Notes

- Unsigned DMGs will trigger Gatekeeper warnings
- Notarization is required for distribution outside the Mac App Store
- After notarization, users can run the app without disabling Gatekeeper

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.