#!/bin/bash
#
# macOS Power Consumption Exporter - Application Launcher
# This script is the entry point for the .app bundle
#

set -e

# Configuration
APP_NAME="MacOS Power Consumption Exporter"
BUNDLE_ID="com.combust.macos-power-consumption-exporter"
HELPER_LABEL="com.combust.macos-power-consumption-exporter"
EXPORTER_PORT="${EXPORTER_PORT:-8080}"
LOG_DIR="$HOME/Library/Logs/com.combust.macos-power-consumption-exporter"
PID_FILE="$HOME/.macos-power-consumption-exporter.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/../MacOS/macos-power-consumption-exporter"

# Create log directory
mkdir -p "$LOG_DIR"

# Check if powermetrics is available
check_powermetrics() {
    if ! command -v powermetrics &> /dev/null; then
        log_error "powermetrics command not found. This application requires macOS."
        osascript -e 'display dialog "powermetrics not found. This application requires macOS." with title "Error" buttons {"OK"} with icon stop'
        exit 1
    fi
}

# Check if running with sudo privileges
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running with sudo privileges"
        return 1
    fi
    return 0
}

# Install launch agent for current user
install_launch_agent() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/${HELPER_LABEL}.plist"

    mkdir -p "$plist_dir"

    # Create launch agent plist
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${HELPER_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_PATH}</string>
        <string>-addr</string>
        <string>:${EXPORTER_PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/exporter.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/exporter.error.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

    log_info "Launch agent installed at $plist_path"
}

# Uninstall launch agent
uninstall_launch_agent() {
    local plist_path="$HOME/Library/LaunchAgents/${HELPER_LABEL}.plist"

    if [ -f "$plist_path" ]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        log_info "Launch agent uninstalled"
    fi
}

# Start the exporter
start_exporter() {
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_info "Exporter is already running (PID: $old_pid)"
            return 0
        fi
    fi

    # Request sudo if needed
    if ! check_sudo; then
        log_warn "Starting without sudo - powermetrics may not work"
    fi

    # Start the exporter
    "$BINARY_PATH" -addr ":$EXPORTER_PORT" &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    log_info "Exporter started (PID: $pid)"
}

# Stop the exporter
stop_exporter() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log_info "Exporter stopped"
        else
            log_warn "Exporter process not found"
            rm -f "$PID_FILE"
        fi
    else
        log_warn "No PID file found"
    fi

    # Also try to stop via launchctl
    launchctl unload "$HOME/Library/LaunchAgents/${HELPER_LABEL}.plist" 2>/dev/null || true
}

# Check if exporter is running
status_exporter() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Exporter is running (PID: $pid)"
            return 0
        fi
    fi

    # Also check via launchctl
    if launchctl list | grep -q "$HELPER_LABEL"; then
        log_info "Exporter is running (via launchctl)"
        return 0
    fi

    log_info "Exporter is not running"
    return 1
}

# Open metrics page in browser
open_metrics() {
    open "http://localhost:${EXPORTER_PORT}/metrics"
}

# Show usage
usage() {
    echo "Usage: $0 {start|stop|status|install|uninstall|open}"
    echo ""
    echo "Commands:"
    echo "  start      Start the exporter"
    echo "  stop       Stop the exporter"
    echo "  status     Check exporter status"
    echo "  install    Install launch agent (auto-start)"
    echo "  uninstall  Uninstall launch agent"
    echo "  open       Open metrics page in browser"
}

# Main
main() {
    check_powermetrics

    case "${1:-status}" in
        start)
            start_exporter
            ;;
        stop)
            stop_exporter
            ;;
        status)
            status_exporter
            ;;
        install)
            install_launch_agent
            start_exporter
            ;;
        uninstall)
            stop_exporter
            uninstall_launch_agent
            ;;
        open)
            open_metrics
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"