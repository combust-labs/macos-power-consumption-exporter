#!/bin/bash
#
# xbar extension for macOS Power Consumption Exporter
# Displays current power metrics in the menu bar
#
# Requirements:
# - xbar app installed: https://xbarapp.com
# - Power exporter running on localhost:8080
#
# Installation:
# 1. Install xbar: brew install xbar
# 2. Create plugins folder: mkdir -p ~/Library/Application\ Support/xbar/plugins
# 3. Copy this script to: ~/Library/Application\ Support/xbar/plugins/power-metrics.10s.sh
# 4. Make executable: chmod +x power-metrics.10s.sh
# 5. Restart xbar
#
# Refresh: This script runs every 10 seconds (change .10s.sh to desired interval)

# Configuration
EXPORTER_BASE="http://localhost:8080"
EXPORTER_URL="${EXPORTER_BASE}/metrics"
METRICS_ENDPOINT="${EXPORTER_URL}"
HEALTH_ENDPOINT="${EXPORTER_BASE}/health"
REFRESH_INTERVAL="10s"

# Colors for output
COLOR_GREEN="green"
COLOR_YELLOW="yellow"
COLOR_RED="red"
COLOR_WHITE="white"

# Get metrics from exporter
get_metrics() {
    curl -s --max-time 5 "$METRICS_ENDPOINT" 2>/dev/null
}

# Parse CPU power from metrics
get_cpu_power() {
    local metrics="$1"
    echo "$metrics" | grep "power_usage_reader_cpu_power" | grep -v "#" | awk '{print $2}' | tail -1
}

# Parse GPU power from metrics
get_gpu_power() {
    local metrics="$1"
    echo "$metrics" | grep "power_usage_reader_gpu_power" | grep -v "#" | awk '{print $2}' | tail -1
}

# Parse ANE power from metrics
get_ane_power() {
    local metrics="$1"
    echo "$metrics" | grep "power_usage_ane_power" | grep -v "#" | awk '{print $2}' | tail -1
}

# Parse combined power from metrics
get_combined_power() {
    local metrics="$1"
    echo "$metrics" | grep "power_usage_combined_power" | grep -v "#" | awk '{print $2}' | tail -1
}

# Format power value with unit
format_power() {
    local power="$1"
    if [ -z "$power" ] || [ "$power" = "NaN" ]; then
        echo "N/A"
    elif (( $(echo "$power > 1000" | bc -l) )); then
        # Convert to watts if > 1000mW
        echo "$(echo "scale=1; $power / 1000" | bc -l)W"
    else
        echo "${power}mW"
    fi
}

# Get status - whether exporter is running
get_status() {
    curl -s --max-time 2 "$HEALTH_ENDPOINT" 2>/dev/null | grep -q "OK" && echo "running" || echo "stopped"
}

# Main
main() {
    local status
    status=$(get_status)

    if [ "$status" = "stopped" ]; then
        # Exporter not running
        echo "⚠️ Power"
        echo "---"
        echo "Exporter not running | color=red"
        echo "Click to start... | bash='open' param='http://localhost:8080/metrics'"
        exit 0
    fi

    # Get metrics
    local metrics
    metrics=$(get_metrics)

    if [ -z "$metrics" ]; then
        echo "⚠️ Power"
        echo "---"
        echo "Failed to fetch metrics | color=red"
        exit 0
    fi

    # Parse values
    local cpu gpu ane combined
    cpu=$(get_cpu_power "$metrics")
    gpu=$(get_gpu_power "$metrics")
    ane=$(get_ane_power "$metrics")
    combined=$(get_combined_power "$metrics")

    # Format values
    local cpu_fmt gpu_fmt ane_fmt combined_fmt
    cpu_fmt=$(format_power "$cpu")
    gpu_fmt=$(format_power "$gpu")
    ane_fmt=$(format_power "$ane")
    combined_fmt=$(format_power "$combined")

    # Menu bar icon based on power level
    local icon="⚡"
    if [ -n "$combined" ] && [ "$combined" != "N/A" ]; then
        if (( $(echo "$combined > 30000" | bc -l) )); then
            icon="🔥"  # High power
        elif (( $(echo "$combined > 15000" | bc -l) )); then
            icon="⚡"  # Medium power
        else
            icon="🔋"  # Low power
        fi
    fi

    # Output menu bar
    echo "${icon} ${combined_fmt}"

    # Output dropdown menu
    echo "---"
    echo "macOS Power Metrics | font=SF Mono Bold"
    echo "---"
    echo "Combined: ${combined_fmt}"
    echo "CPU: ${cpu_fmt}"
    echo "GPU: ${gpu_fmt}"
    echo "ANE: ${ane_fmt}"
    echo "---"
    echo "Refresh | refresh=true"
    echo "---"
    echo "Open Metrics | href=http://localhost:8080/metrics"
    echo "Open Health | href=http://localhost:8080/health"
}

main "$@"