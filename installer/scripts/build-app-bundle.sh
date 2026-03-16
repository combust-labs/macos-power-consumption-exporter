#!/bin/bash
#
# Build Script for macOS Power Consumption Exporter App Bundle
# Creates a proper .app application bundle
#

set -e

# Configuration
APP_NAME="MacOS Power Consumption Exporter"
APP_BUNDLE_ID="com.combust.macos-power-consumption-exporter"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="${PWD}/build"
SOURCE_DIR="${PWD}"

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
    echo "  -o, --output DIR     Output directory (default: ./build)"
    echo "  -v, --version VER    Version string (default: 1.0.0)"
    echo "  -h, --help           Show this help"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            BUILD_DIR="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
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

log_info "Building ${APP_NAME} v${VERSION}"
log_info "Output directory: ${BUILD_DIR}"

# Clean build directory
log_step "Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Step 1: Build the Go binary
log_step "Building Go binary..."

cd "${SOURCE_DIR}"

# Get version info
GIT_VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Build the binary
LDFLAGS="-X main.Version=${GIT_VERSION} -X main.Commit=${GIT_COMMIT}"

if ! go build -ldflags "${LDFLAGS}" -o "${BUILD_DIR}/macos-power-consumption-exporter" ./cmd/main.go; then
    log_error "Failed to build Go binary"
    exit 1
fi

log_info "Binary built: ${BUILD_DIR}/macos-power-consumption-exporter"

# Step 2: Create app bundle structure
log_step "Creating app bundle structure..."

APP_BUNDLE_PATH="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_PATH="${APP_BUNDLE_PATH}/Contents"
MACOS_PATH="${CONTENTS_PATH}/MacOS"
RESOURCES_PATH="${CONTENTS_PATH}/Resources"

mkdir -p "${MACOS_PATH}"
mkdir -p "${RESOURCES_PATH}"

# Step 3: Copy binary
log_step "Copying binary..."
cp "${BUILD_DIR}/macos-power-consumption-exporter" "${MACOS_PATH}/"

# Step 4: Copy launcher script
log_step "Copying launcher script..."
cp "${SOURCE_DIR}/installer/app/launcher.sh" "${MACOS_PATH}/launcher"
chmod +x "${MACOS_PATH}/launcher"

# Step 5: Create Info.plist
log_step "Creating Info.plist..."

# Get version from git tags or use default
sed -e "s/\${VERSION}/${VERSION}/g" \
    -e "s/\${APP_BUNDLE_ID}/${APP_BUNDLE_ID}/g" \
    -e "s/\${APP_NAME}/${APP_NAME}/g" \
    "${SOURCE_DIR}/installer/templates/Info.plist" > "${CONTENTS_PATH}/Info.plist"

# Step 6: Copy entitlements
log_step "Copying entitlements..."
cp "${SOURCE_DIR}/installer/templates/entitlements.plist" "${CONTENTS_PATH}/"

# Step 7: Create PkgInfo
log_step "Creating PkgInfo..."
echo -n "APPL????" > "${CONTENTS_PATH}/PkgInfo"

# Step 8: Create a simple icon (placeholder)
# In production, you'd use a proper icon file
log_step "Note: No icon file provided - using default"

# Step 9: Verify bundle
log_step "Verifying bundle structure..."
echo ""
echo "Bundle structure:"
ls -la "${APP_BUNDLE_PATH}/"
echo ""
echo "Contents:"
ls -la "${CONTENTS_PATH}/"
echo ""
echo "MacOS:"
ls -la "${MACOS_PATH}/"
echo ""

# Step 10: Set permissions
log_step "Setting permissions..."
chmod -R 755 "${APP_BUNDLE_PATH}"

# Summary
log_info "========================================="
log_info "App bundle created successfully!"
log_info "Path: ${APP_BUNDLE_PATH}"
log_info "Version: ${VERSION}"
log_info "========================================="
log_info ""
log_info "Next steps:"
log_info "  1. Add an icon to: ${RESOURCES_PATH}/icon.icns"
log_info "  2. Create DMG: ./installer/scripts/create-dmg.sh --app '${APP_BUNDLE_PATH}'"
log_info "  3. Sign the app: codesign --deep --force --sign 'Your Certificate' '${APP_BUNDLE_PATH}'"
log_info ""

exit 0