#!/bin/bash
#
# DMG Creation Script for macOS Power Consumption Exporter
# Creates a distributable DMG with the application bundle
#

set -e

# Configuration
APP_NAME="MacOS Power Consumption Exporter"
APP_BUNDLE_ID="com.combust.macos-power-consumption-exporter"
VOLUME_NAME="${APP_NAME}"
DMG_FILENAME="${APP_NAME}.dmg"
SOURCE_APP_PATH=""
OUTPUT_DIR="${PWD}"

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

# Show usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -a, --app PATH       Path to the .app bundle"
    echo "  -o, --output DIR     Output directory for DMG (default: current directory)"
    echo "  -n, --name NAME      Volume name (default: ${APP_NAME})"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Example:"
    echo "  $0 --app ./build/MacOS\\ Power\\ Consumption\\ Exporter.app --output ./dist"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app)
            SOURCE_APP_PATH="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--name)
            VOLUME_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$SOURCE_APP_PATH" ]; then
    log_error "Please specify the .app bundle path with --app"
    exit 1
fi

if [ ! -d "$SOURCE_APP_PATH" ]; then
    log_error "App bundle not found: $SOURCE_APP_PATH"
    exit 1
fi

# Get absolute path
SOURCE_APP_PATH="$(cd "$SOURCE_APP_PATH" && pwd)"
APP_BASENAME="$(basename "$SOURCE_APP_PATH" .app)"

log_info "Creating DMG for: $APP_BASENAME"
log_info "Source: $SOURCE_APP_PATH"
log_info "Output: $OUTPUT_DIR"

# Create temporary directory for DMG contents
TEMP_DIR=$(mktemp -d)
DMG_TEMP_PATH="${TEMP_DIR}/${VOLUME_NAME}.dmg"
FINAL_DMG_PATH="${OUTPUT_DIR}/${APP_BASENAME}.dmg"

cleanup() {
    log_info "Cleaning up..."
    # Unmount any mounted DMG
    hdiutil detach "/Volumes/${VOLUME_NAME}" 2>/dev/null || true
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# Step 1: Create the DMG structure
log_step "Creating DMG structure..."

mkdir -p "${TEMP_DIR}/dmg-root"
mkdir -p "${TEMP_DIR}/dmg-root/Applications"

# Copy the app bundle
cp -R "$SOURCE_APP_PATH" "${TEMP_DIR}/dmg-root/Applications/"

# Create README
cat > "${TEMP_DIR}/dmg-root/README.txt" << 'EOF'
# macOS Power Consumption Exporter

## Installation

1. Drag "MacOS Power Consumption Exporter" to the Applications folder
2. Enable auto-start at boot (run from Terminal):
   sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" install
3. Access metrics at http://localhost:8080/metrics

## Auto-Start

The exporter uses a LaunchDaemon to start automatically at system boot.
To manage it (from the app bundle):

    # Enable auto-start at boot
    sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" install

    # Other commands
    sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" start
    sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" stop
    sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" status
    sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" logs

Logs are written to:
    /var/log/combust-macos-power-consumption-exporter.log
    /var/log/combust-macos-power-consumption-exporter.error.log

## Usage

Access the metrics endpoint:
    http://localhost:8080/metrics

Health check:
    http://localhost:8080/health

## Uninstall

1. Drag the application to Trash
2. Run: sudo "/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/launchdaemon.sh" uninstall

## Support

For issues and feedback, visit:
https://github.com/combust-labs/macos-power-consumption-exporter
EOF

# Step 2: Calculate size and create DMG
log_step "Creating DMG with hdiutil..."

# Calculate size (add some buffer)
APP_SIZE=$(du -sk "$SOURCE_APP_PATH" | cut -f1)
DMG_SIZE=$((APP_SIZE * 2 / 1024 + 50000)) # Size in MB

# Remove existing DMG if present
if [ -f "$FINAL_DMG_PATH" ]; then
    rm -f "$FINAL_DMG_PATH"
fi

# Create DMG using the folder method
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -fs "HFS+" \
    -size "${DMG_SIZE}m" \
    -imagekey zlib-level=9 \
    -srcfolder "${TEMP_DIR}/dmg-root" \
    -ov \
    "$FINAL_DMG_PATH"

if [ $? -ne 0 ]; then
    log_error "Failed to create DMG"
    exit 1
fi

# Step 3: Verify
log_step "Verifying DMG..."

if hdiutil attach "$FINAL_DMG_PATH" -nobrowse; then
    log_info "DMG verified successfully"
    hdiutil detach "/Volumes/${VOLUME_NAME}" 2>/dev/null || true
else
    log_error "DMG verification failed"
    exit 1
fi

# Step 4: Get DMG info
log_step "DMG Information:"
hdiutil info "$FINAL_DMG_PATH" 2>/dev/null | grep -E "(format|size)" | head -5

log_info "========================================="
log_info "DMG created successfully!"
log_info "Output: $FINAL_DMG_PATH"
log_info "========================================="

# Optionally suggest create-dmg if available
if command -v create-dmg &> /dev/null; then
    log_info ""
    log_info "Note: For a prettier DMG with custom icon and window position,"
    log_info "you can use the 'create-dmg' tool:"
    log_info "  create-dmg --volname '${VOLUME_NAME}' \\"
    log_info "    --volicon 'path/to/icon.icns' \\"
    log_info "    --window-pos 200 120 \\"
    log_info "    --window-size 600 400 \\"
    log_info "    '${FINAL_DMG_PATH}' \\"
    log_info "    '${TEMP_DIR}/dmg-root/'"
fi

exit 0