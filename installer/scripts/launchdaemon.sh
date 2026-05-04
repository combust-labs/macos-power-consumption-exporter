#!/bin/bash
#
# LaunchDaemon management script for macOS Power Consumption Exporter
# This script installs/removes/configures the LaunchDaemon for system boot startup
#

set -e

# Configuration
DAEMON_LABEL="com.combust.macos-power-consumption-exporter"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
EXPORTER_ADDR="${EXPORTER_ADDR:-:8080}"
EXPORTER_PORT_FILE="${EXPORTER_PORT_FILE:-}"
EXPORTER_PORT_RANGE_START="${EXPORTER_PORT_RANGE_START:-8000}"
EXPORTER_PORT_RANGE_END="${EXPORTER_PORT_RANGE_END:-9000}"
LOG_LEVEL="${LOG_LEVEL:-info}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Find the binary path
find_binary() {
    local binary_name="macos-power-consumption-exporter"
    
    # Check common locations
    local locations=(
        "/usr/local/bin/${binary_name}"
        "/opt/homebrew/bin/${binary_name}"
        "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/${binary_name}"
        "$(cd "${BASH_SOURCE%/*}/../.." && pwd)/${binary_name}"
    )
    
    for loc in "${locations[@]}"; do
        if [ -f "$loc" ] && [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done
    
    # Fallback: check if it's in PATH
    if command -v "$binary_name" &> /dev/null; then
        which "$binary_name"
        return 0
    fi
    
    return 1
}

# Install the LaunchDaemon
install() {
    check_root
    
    log_info "Installing ${DAEMON_LABEL} LaunchDaemon..."
    
    # Find the binary
    local binary_path
    binary_path=$(find_binary) || {
        log_error "Could not find macos-power-consumption-exporter binary"
        log_info "Please either:"
        log_info "  1. Run 'sudo make install' first to install the binary"
        log_info "  2. Or specify the binary path manually"
        exit 1
    }
    
    log_info "Found binary at: $binary_path"
    
    # Create the plist content directly (no external template needed)
    local plist_content
    
    # Build environment variables section
    local env_vars=""
    env_vars+="        <key>PATH</key>\n"
    env_vars+="        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>\n"
    if [ -n "$EXPORTER_PORT_FILE" ]; then
        env_vars+="        <key>EXPORTER_PORT_FILE</key>\n"
        env_vars+="        <string>${EXPORTER_PORT_FILE}</string>\n"
    fi
    env_vars+="        <key>EXPORTER_PORT_RANGE_START</key>\n"
    env_vars+="        <string>${EXPORTER_PORT_RANGE_START}</string>\n"
    env_vars+="        <key>EXPORTER_PORT_RANGE_END</key>\n"
    env_vars+="        <string>${EXPORTER_PORT_RANGE_END}</string>\n"
    
    plist_content=$(cat << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${DAEMON_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${binary_path}</string>
        <string>-addr</string>
        <string>${EXPORTER_ADDR}</string>
        <string>-log-level</string>
        <string>${LOG_LEVEL}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/combust-macos-power-consumption-exporter.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/combust-macos-power-consumption-exporter.error.log</string>
    <key>ProcessType</key>
    <string>Background</string>
    <key>EnvironmentVariables</key>
    <dict>
${env_vars}    </dict>
</dict>
</plist>
PLIST_EOF
)
    
    # Write the plist
    mkdir -p "$(dirname "$DAEMON_PLIST")"
    printf '%s' "$plist_content" > "$DAEMON_PLIST"
    chmod 644 "$DAEMON_PLIST"
    
    log_info "Created ${DAEMON_PLIST}"
    
    # Load the LaunchDaemon
    launchctl load "$DAEMON_PLIST"
    
    log_info "LaunchDaemon loaded and will start at next boot"
    log_info ""
    log_info "The exporter will automatically start when the system boots."
    log_info "Access metrics at: http://localhost${EXPORTER_ADDR}/metrics"
    log_info "Health check at:   http://localhost${EXPORTER_ADDR}/health"
    log_info ""
    log_info "Logs are available at:"
    log_info "  /var/log/combust-macos-power-consumption-exporter.log"
    log_info "  /var/log/combust-macos-power-consumption-exporter.error.log"
    if [ "$EXPORTER_ADDR" = ":0" ]; then
        log_info "Port file: ${EXPORTER_PORT_FILE:-~/.macos-power-consumption-exporter-port-file}"
    fi
}

# Uninstall the LaunchDaemon
uninstall() {
    check_root
    
    log_info "Uninstalling ${DAEMON_LABEL} LaunchDaemon..."
    
    # Stop if running
    if launchctl list | grep -q "$DAEMON_LABEL"; then
        launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
        log_info "Stopped the daemon"
    fi
    
    # Remove the plist
    if [ -f "$DAEMON_PLIST" ]; then
        rm -f "$DAEMON_PLIST"
        log_info "Removed ${DAEMON_PLIST}"
    else
        log_warn "LaunchDaemon plist not found (may not be installed)"
    fi
    
    log_info "Uninstall complete"
}

# Start the LaunchDaemon
start() {
    check_root
    
    if [ ! -f "$DAEMON_PLIST" ]; then
        log_error "LaunchDaemon not installed. Run 'sudo ./launchdaemon.sh install' first."
        exit 1
    fi
    
    launchctl load "$DAEMON_PLIST"
    log_info "LaunchDaemon started"
}

# Stop the LaunchDaemon
stop() {
    check_root
    
    if launchctl list | grep -q "$DAEMON_LABEL"; then
        launchctl unload "$DAEMON_PLIST"
        log_info "LaunchDaemon stopped"
    else
        log_warn "LaunchDaemon is not running"
    fi
}

# Restart the LaunchDaemon
restart() {
    stop
    sleep 1
    start
}

# Show status
status() {
    local pid
    pid=$(launchctl list | grep "$DAEMON_LABEL" | awk '{print $1}' | head -1)
    
    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
        log_info "LaunchDaemon is running (PID: $pid)"
        echo ""
        echo "Address:     http://localhost${EXPORTER_ADDR}/metrics"
        echo "Health:      http://localhost${EXPORTER_ADDR}/health"
        echo "Log (out):   /var/log/combust-macos-power-consumption-exporter.log"
        echo "Log (err):   /var/log/combust-macos-power-consumption-exporter.error.log"
    else
        log_info "LaunchDaemon is not running"
        echo ""
        echo "To install and start: sudo ./launchdaemon.sh install"
    fi
}

# Show logs
logs() {
    echo "=== Standard Out Log ==="
    tail -50 /var/log/combust-macos-power-consumption-exporter.log 2>/dev/null || echo "No log file found"
    echo ""
    echo "=== Standard Error Log ==="
    tail -50 /var/log/combust-macos-power-consumption-exporter.error.log 2>/dev/null || echo "No error log found"
}

# Show usage
usage() {
    echo "Usage: $0 {install|uninstall|start|stop|restart|status|logs}"
    echo ""
    echo "Commands:"
    echo "  install    Install LaunchDaemon and start at boot"
    echo "  uninstall  Stop and remove LaunchDaemon"
    echo "  start      Start the LaunchDaemon now"
    echo "  stop       Stop the LaunchDaemon"
    echo "  restart    Restart the LaunchDaemon"
    echo "  status     Show if the daemon is running"
    echo "  logs       Show recent log output"
    echo ""
    echo "Environment variables:"
    echo "  EXPORTER_ADDR            Address for the HTTP server (default: :8080)"
    echo "                           Use ':0' for ephemeral port selection"
    echo "  EXPORTER_PORT_FILE       Path to port file for ephemeral mode"
    echo "  EXPORTER_PORT_RANGE_START Start of port range for ephemeral (default: 8000)"
    echo "  EXPORTER_PORT_RANGE_END   End of port range for ephemeral (default: 9000)"
    echo "  LOG_LEVEL                Log level: debug, info, warn, error (default: info)"
    echo ""
    echo "Examples:"
    echo "  sudo ./launchdaemon.sh install"
    echo "  sudo EXPORTER_ADDR=:9090 ./launchdaemon.sh install"
    echo "  sudo LOG_LEVEL=debug ./launchdaemon.sh install"
    echo ""
    echo "Ephemeral port mode (random available port, written to file):"
    echo "  sudo EXPORTER_ADDR=:0 \\"
    echo "       EXPORTER_PORT_FILE=$HOME/.macos-power-exporter-port.txt \\"
    echo "       ./launchdaemon.sh install"
}

# Main
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    case "$1" in
        install)
            install
            ;;
        uninstall)
            uninstall
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            restart
            ;;
        status)
            status
            ;;
        logs)
            logs
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"