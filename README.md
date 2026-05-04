# macOS Power Usage Prometheus Exporter

![Go](https://img.shields.io/badge/Go-1.26+-00ADD8?style=flat&logo=go)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

This program exports the power usage of your macOS device as Prometheus metrics.

## Features

- Exports CPU, GPU, ANE (Apple Neural Engine), and combined power usage
- Prometheus metrics with hostname label
- Bearer token authentication for /metrics endpoint (optional)
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

### DMG Installer (Recommended for macOS)

For a native macOS installation experience, build a DMG from source:

```bash
# Build unsigned DMG (for development/testing)
make dmg-unsigned

# Build signed DMG (requires Developer ID certificate)
make dmg
```

The DMG will be created at `dist/MacOS Power Consumption Exporter.dmg`.

**After installing from DMG:**

1. Double-click the DMG to mount it
2. Drag "MacOS Power Consumption Exporter" to the Applications folder
3. Enable auto-start at boot:
   ```bash
   sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" install
   ```

### pico-xbar Integration (Optional)

For a menu bar display of power metrics, use **[pico-xbar](https://github.com/laborin/pico-xbar)** (a maintained xbar alternative):

#### Installation

**pico-xbar** is a maintained xbar alternative, installed via:

```bash
# Via Homebrew (recommended)
brew install laborin/tap/pico-xbar

# Or download release from: https://github.com/laborin/pico-xbar/releases
# Then put the binary on your PATH
```

#### Setup

pico-xbar is 100% xbar compatible, so plugins go in the standard xbar directory:

```bash
# Create plugins directory
mkdir -p ~/Library/Application\ Support/xbar/plugins

# Copy the power metrics plugin
cp installer/xbar/power-metrics-simple.sh ~/Library/Application\ Support/xbar/plugins/power-metrics.10s.sh

# Make executable
chmod +x ~/Library/Application\ Support/xbar/plugins/power-metrics.10s.sh

# Restart pico-xbar (or click Refresh)
```

#### Features

The plugin displays:
- **Menu bar icon**: ⚡ (or 🔥 for high power, 🔋 for low power)
- **Combined power** in the menu bar (e.g., "⚡ 2.5W")
- **Dropdown menu** with:
  - Combined, CPU, GPU, ANE power values
  - Links to open metrics/health in browser
  - Options to restart/stop exporter
  - Auto-refresh every 10 seconds

#### Customization

| File | Description |
|------|-------------|
| `installer/xbar/power-metrics.sh` | Full version with colors and more features |
| `installer/xbar/power-metrics-simple.sh` | Simpler version (no bc required) |

To change refresh rate, rename the file (e.g., `power-metrics.30s.sh` for 30 seconds).

#### Accessing Metrics

Once running, access the metrics at:

| Endpoint | Description |
|----------|-------------|
| http://localhost:8080/metrics | Prometheus metrics |
| http://localhost:8080/health | Health check |

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

### Auto-Start at Boot (LaunchDaemon)

For automatic startup when the system boots (runs as root), use the LaunchDaemon approach:

#### If Installed via DMG

```bash
# Enable auto-start at boot
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" install
```

#### If Built from Source

```bash
# Install and enable auto-start at boot
sudo make launchdaemon-install

# Or with custom options
sudo EXPORTER_PORT=9090 LOG_LEVEL=debug make launchdaemon-install
```

#### LaunchDaemon Management

**From installed app:**
```bash
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" install
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" start
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" stop
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" status
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" logs
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" uninstall
```

**From source tree:**
```bash
make launchdaemon-install    # Install and start at boot
make launchdaemon-uninstall  # Remove auto-start
make launchdaemon-start      # Start now
make launchdaemon-stop       # Stop running
exporter
make launchdaemon-status     # Check if running
make launchdaemon-logs       # View recent logs
```

**Note:** LaunchDaemon runs at system boot (not user login). Logs are written to `/var/log/combust-macos-power-consumption-exporter.log`.

### Command-line Options

| Flag | Default | Description |
|------|---------|-------------|
| `-addr` | `:8080` | HTTP server address |
| `-log-level` | `info` | Log level (debug, info, warn, error) |
| `-auth-header-file` | `` | Path to file containing auth token (enables Bearer token auth on /metrics) |

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
    bearer_token: 'my-secret-token'
    static_configs:
      - targets: ['localhost:8080']
```

If using authentication, configure the `bearer_token` in your Prometheus scrape config to match the token in your token file.

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
| `/metrics` | Prometheus metrics endpoint (protected by auth if configured) |
| `/health` | Health check endpoint (always public) |

## Bearer Token Authentication

Optionally protect the `/metrics` endpoint with Bearer token authentication:

```bash
# Create a token file
echo "my-secret-token" > /path/to/token.txt

# Run with auth enabled
sudo ./macos-power-consumption-exporter --auth-header-file /path/to/token.txt
```

**Accessing protected metrics:**
```bash
# With token
curl -H "Authorization: Bearer my-secret-token" http://localhost:8080/metrics

# Without token (returns 401 Unauthorized)
curl http://localhost:8080/metrics
```

The `/health` endpoint remains unauthenticated.


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

The `powermetrics` command requires sudo permissions. Options:

```bash
# Option 1: Run directly with sudo
sudo ./macos-power-consumption-exporter

# Option 2: Use LaunchDaemon (auto-starts at boot as root)
sudo make launchdaemon-install
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

### LaunchDaemon Not Starting at Boot

If the LaunchDaemon isn't starting at boot:

```bash
# Check status
make launchdaemon-status

# Manually load
sudo launchctl load /Library/LaunchDaemons/com.combust.macos-power-consumption-exporter.plist

# Check system logs
tail -f /var/log/system.log | grep combust
```

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

### Via LaunchDaemon

If you installed via LaunchDaemon:

```bash
# From installed app bundle
sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" uninstall

# Or from source tree
sudo make launchdaemon-uninstall
```

### What Gets Removed

The uninstall script removes:
- Application bundle from `/Applications` or `~/Applications`
- LaunchDaemon (`/Library/LaunchDaemons/com.combust.macos-power-consumption-exporter.plist`)
- Log files (`/var/log/combust-macos-power-consumption-exporter*.log`)
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
