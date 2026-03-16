#!/bin/bash
#
# xbar extension - Simple Version (no bc required)
# Displays current power metrics in the menu bar
#
# Installation:
# 1. Install xbar: brew install xbar
# 2. Copy to: ~/Library/Application\ Support/xbar/plugins/power-metrics.10s.sh
# 3. chmod +x power-metrics.10s.sh
# 4. Restart xbar

EXPORTER_BASE="http://localhost:8080"
EXPORTER_URL="${EXPORTER_BASE}/metrics"
HEALTH_ENDPOINT="${EXPORTER_BASE}/health"

# Get combined power
get_combined() {
    curl -s --max-time 3 "$EXPORTER_URL" 2>/dev/null | \
        grep "power_usage_combined_power" | grep -v "#" | \
        awk '{print $2}' | tail -1
}

# Get CPU power
get_cpu() {
    curl -s --max-time 3 "$EXPORTER_URL" 2>/dev/null | \
        grep "power_usage_reader_cpu_power" | grep -v "#" | \
        awk '{print $2}' | tail -1
}

# Get GPU power
get_gpu() {
    curl -s --max-time 3 "$EXPORTER_URL" 2>/dev/null | \
        grep "power_usage_reader_gpu_power" | grep -v "#" | \
        awk '{print $2}' | tail -1
}

# Get ANE power
get_ane() {
    curl -s --max-time 3 "$EXPORTER_URL" 2>/dev/null | \
        grep "power_usage_ane_power" | grep -v "#" | \
        awk '{print $2}' | tail -1
}

# Check if exporter is running
is_running() {
    curl -s --max-time 2 "$HEALTH_ENDPOINT" 2>/dev/null | grep -q "OK"
}

# Format power value
format_power() {
    local val="$1"
    if [ -z "$val" ] || [ "$val" = "NaN" ]; then
        echo "N/A"
    elif [ "$val" -gt 1000 ] 2>/dev/null; then
        echo "$((val / 1000))W"
    else
        echo "${val}mW"
    fi
}

# Main
main() {
    if ! is_running; then
        echo "⚠️ Off"
        echo "---"
        echo "Exporter not running | color=red"
        echo "Run: sudo ./launcher install | bash='sudo' param='/Applications/MacOS\\ Power\\ Consumption\\ Exporter.app/Contents/MacOS/launcher install' terminal=true"
        exit 0
    fi

    local combined cpu gpu ane
    combined=$(get_combined)
    cpu=$(get_cpu)
    gpu=$(get_gpu)
    ane=$(get_ane)

    local combined_fmt cpu_fmt gpu_fmt ane_fmt
    combined_fmt=$(format_power "$combined")
    cpu_fmt=$(format_power "$cpu")
    gpu_fmt=$(format_power "$gpu")
    ane_fmt=$(format_power "$ane")

    # Choose icon based on power level
    local icon="⚡"
    if [ -n "$combined" ] && [ "$combined" != "N/A" ]; then
        if [ "$combined" -gt 30000 ] 2>/dev/null; then
            icon="🔥"
        elif [ "$combined" -lt 5000 ] 2>/dev/null; then
            icon="🔋"
        fi
    fi

    # Output
    echo "${icon} ${combined_fmt}"
    echo "---"
    echo "Power Metrics | font=SF Mono Bold"
    echo "---"
    echo "Combined: ${combined_fmt}"
    echo "CPU: ${cpu_fmt}"
    echo "GPU: ${gpu_fmt}"
    echo "ANE: ${ane_fmt}"
    echo "---"
    echo "Refresh | refresh=true"
    echo "Open Metrics | href=http://localhost:8080/metrics"
    echo "Open Health | href=http://localhost:8080/health"
}

main "$@"