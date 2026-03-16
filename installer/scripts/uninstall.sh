#!/bin/bash
#
# macOS Power Consumption Exporter - Uninstall Script
# Removes the application, launch agent, and all related files
#

set -e

# Configuration
APP_NAME="MacOS Power Consumption Exporter"
APP_BUNDLE_ID="com.combust.macos-power-consumption-exporter"
HELPER_LABEL="${APP_BUNDLE_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running with sudo - some operations may fail"
        return 1
    fi
    return 0
}

# Stop the exporter if running
stop_exporter() {
    log_step "Stopping exporter..."

    # Try to stop via launchctl
    if launchctl list | grep -q "$HELPER_LABEL"; then
        launchctl unload "$HOME/Library/LaunchAgents/${HELPER_LABEL}.plist" 2>/dev/null || true
        log_info "Launch agent unloaded"
    fi

    # Kill any running process
    if pgrep -f "macos-power-consumption-exporter" > /dev/null; then
        pkill -f "macos-power-consumption-exporter" 2>/dev/null || true
        log_info "Exporter process killed"
    fi

    # Remove PID file
    if [ -f "$HOME/.macos-power-consumption-exporter.pid" ]; then
        rm -f "$HOME/.macos-power-consumption-exporter.pid"
        log_info "PID file removed"
    fi
}

# Remove launch agent
remove_launch_agent() {
    log_step "Removing launch agent..."

    local plist_path="$HOME/Library/LaunchAgents/${HELPER_LABEL}.plist"

    if [ -f "$plist_path" ]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        log_info "Launch agent removed: $plist_path"
    else
        log_info "No launch agent found"
    fi
}

# Remove application from /Applications
remove_from_applications() {
    log_step "Removing application from /Applications..."

    local app_path="/Applications/${APP_NAME}.app"

    if [ -d "$app_path" ]; then
        rm -rf "$app_path"
        log_info "Application removed from /Applications"
    else
        log_info "Application not found in /Applications"
    fi
}

# Remove from user's local Applications (if installed there)
remove_from_user_applications() {
    log_step "Removing application from user Applications..."

    local app_path="$HOME/Applications/${APP_NAME}.app"

    if [ -d "$app_path" ]; then
        rm -rf "$app_path"
        log_info "Application removed from ~/Applications"
    else
        log_info "Application not found in ~/Applications"
    fi
}

# Remove log files
remove_logs() {
    log_step "Removing log files..."

    local log_dir="$HOME/Library/Logs/com.combust.macos-power-consumption-exporter"

    if [ -d "$log_dir" ]; then
        rm -rf "$log_dir"
        log_info "Log directory removed: $log_dir"
    else
        log_info "No log directory found"
    fi
}

# Remove cached data
remove_cached_data() {
    log_step "Removing cached data..."

    local cache_dir="$HOME/Library/Caches/${APP_BUNDLE_ID}"

    if [ -d "$cache_dir" ]; then
        rm -rf "$cache_dir"
        log_info "Cache directory removed: $cache_dir"
    else
        log_info "No cache directory found"
    fi
}

# Remove preference files
remove_preferences() {
    log_step "Removing preference files..."

    local prefs_dir="$HOME/Library/Preferences/${APP_BUNDLE_ID}"

    if [ -d "$prefs_dir" ]; then
        rm -rf "$prefs_dir"
        log_info "Preferences removed: $prefs_dir"
    else
        log_info "No preference files found"
    fi

    # Also remove the plist
    local plist_path="$HOME/Library/Preferences/com.combust.macos-power-consumption-exporter.plist"
    if [ -f "$plist_path" ]; then
        rm -f "$plist_path"
        log_info "Preferences plist removed"
    fi
}

# Summary
show_summary() {
    log_info "========================================="
    log_info "Uninstallation complete!"
    log_info "========================================="
    echo ""
    echo "Removed:"
    echo "  - Application bundle"
    echo "  - Launch agent"
    echo "  - Log files"
    echo "  - Cache files"
    echo "  - Preference files"
    echo ""
    echo "Note: You may need to manually empty Trash to complete removal."
}

# Main
main() {
    echo "========================================="
    echo "  ${APP_NAME} Uninstall"
    echo "========================================="
    echo ""

    # Check for --force flag
    FORCE=false
    for arg in "$@"; do
        if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
            FORCE=true
        fi
    done

    # Confirmation prompt (unless --force is used)
    if [ "$FORCE" != "true" ]; then
        echo "This will remove:"
        echo "  - Application from /Applications"
        echo "  - Launch agent (auto-start)"
        echo "  - Log files"
        echo "  - Cache and preference files"
        echo ""
        read -p "Are you sure you want to uninstall? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Uninstall cancelled"
            exit 0
        fi
    fi

    # Perform uninstallation
    stop_exporter
    remove_launch_agent
    remove_from_applications
    remove_from_user_applications
    remove_logs
    remove_cached_data
    remove_preferences

    show_summary
}

main "$@"