.PHONY: build test clean install run help app-bundle dmg dmg-unsigned launchdaemon-install launchdaemon-uninstall launchdaemon-start launchdaemon-stop launchdaemon-status

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOTEST=$(GOCMD) test
GOCLEAN=$(GOCMD) clean
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod
GOLINT=$(GOCMD) vet
GOFMT=$(GOCMD) fmt

# Binary name
BINARY_NAME=macos-power-consumption-exporter
APP_NAME=MacOS Power Consumption Exporter

# Go build variables
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS=-ldflags "-X main.Version=$(VERSION) -X main.Commit=$(COMMIT)"

# Installer paths
INSTALLER_DIR=installer
SCRIPTS_DIR=$(INSTALLER_DIR)/scripts
BUILD_DIR=build

# Default target
help:
	@echo "Available targets:"
	@echo "  build       - Build the binary"
	@echo "  test        - Run tests"
	@echo "  clean       - Clean build artifacts"
	@echo "  install     - Install dependencies"
	@echo "  run         - Run the application"
	@echo "  app-bundle  - Build macOS app bundle (.app)"
	@echo "  dmg         - Build DMG installer (requires app-bundle first)"
	@echo "  dmg-unsigned - Build unsigned DMG for development"
	@echo "  sign        - Code sign the app bundle"
	@echo "  notarize    - Notarize the app bundle (requires signing first)"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "  launchdaemon-install   - Install LaunchDaemon (auto-start at boot)"
	@echo "  launchdaemon-uninstall - Remove LaunchDaemon"
	@echo "  launchdaemon-start     - Start the LaunchDaemon now"
	@echo "  launchdaemon-stop      - Stop the LaunchDaemon"
	@echo "  launchdaemon-status    - Show LaunchDaemon status"
	@echo "  launchdaemon-logs      - Show recent logs"

# Build the binary
build:
	@echo "Building $(BINARY_NAME)..."
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME) ./cmd/main.go
	@echo "Built $(BINARY_NAME)"

# Run tests
test:
	@echo "Running tests..."
	$(GOTEST) -v -race -coverprofile=coverage.out -covermode=atomic ./...
	@echo "Tests complete"

# Run tests without coverage
test-fast:
	@echo "Running tests..."
	$(GOTEST) -v -race ./...
	@echo "Tests complete"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -f $(BINARY_NAME)
	rm -f coverage.out
	rm -rf $(BUILD_DIR)
	rm -rf dist
	@echo "Clean complete"

# Install dependencies
install:
	@echo "Installing dependencies..."
	$(GOMOD) download
	$(GOMOD) tidy
	@echo "Install complete"

# Run the application
run: build
	@echo "Running $(BINARY_NAME)..."
	@echo "Note: This requires sudo to run powermetrics"
	sudo ./$(BINARY_NAME)

# Run with custom address
run-addr: build
	@echo "Running $(BINARY_NAME) with custom address..."
	sudo ./$(BINARY_NAME) -addr :9090

# Format code
fmt:
	$(GOFMT) -w ./...
	@echo "Code formatted"

# Lint code
lint:
	$(GOLINT) ./...
	@echo "Lint complete"

# Show version
version:
	@echo "Version: $(VERSION)"
	@echo "Commit: $(COMMIT)"

# Build macOS app bundle
app-bundle:
	@echo "Building macOS app bundle..."
	@chmod +x $(SCRIPTS_DIR)/build-app-bundle.sh
	@$(SCRIPTS_DIR)/build-app-bundle.sh -o $(BUILD_DIR) -v $(VERSION)
	@echo "App bundle built: $(BUILD_DIR)/$(APP_NAME).app"

# Build DMG installer
dmg: app-bundle
	@echo "Building DMG installer..."
	@chmod +x $(SCRIPTS_DIR)/create-dmg.sh
	@$(SCRIPTS_DIR)/create-dmg.sh --app "./$(BUILD_DIR)/$(APP_NAME).app" --output ./dist
	@echo "DMG built: ./dist/$(APP_NAME).dmg"

# Build unsigned DMG (for development/testing)
dmg-unsigned: app-bundle
	@echo "Building unsigned DMG..."
	@chmod +x $(SCRIPTS_DIR)/create-dmg.sh
	@mkdir -p dist
	@$(SCRIPTS_DIR)/create-dmg.sh --app "./$(BUILD_DIR)/$(APP_NAME).app" --output dist
	@echo "Unsigned DMG built: ./dist/$(APP_NAME).dmg"

# Code sign the app bundle
sign:
	@echo "Code signing app bundle..."
	@if [ -z "$$CERTIFICATE" ]; then \
		echo "Set CERTIFICATE environment variable, e.g., export CERTIFICATE='Developer ID Application: Your Name'"; \
		exit 1; \
	fi
	@codesign --deep --force --sign "$$CERTIFICATE" --entitlements $(INSTALLER_DIR)/templates/entitlements.plist "$(BUILD_DIR)/$(APP_NAME).app"
	@echo "App bundle signed"

# Notarize the app bundle
notarize:
	@echo "Notarizing app bundle..."
	@if [ -z "$$APPLE_ID" ]; then \
		echo "Set APPLE_ID environment variable"; \
		exit 1; \
	fi
	@if [ -z "$$APP_PASSWORD" ]; then \
		echo "Set APP_PASSWORD environment variable (app-specific password)"; \
		exit 1; \
	fi
	@if [ -z "$$TEAM_ID" ]; then \
		echo "Set TEAM_ID environment variable"; \
		exit 1; \
	fi
	@xcrun notarytool submit "$(BUILD_DIR)/$(APP_NAME).app" --apple-id "$$APPLE_ID" --password "$$APP_PASSWORD" --team-id "$$TEAM_ID"
	@echo "Notarization submitted - wait for approval"
	@xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).app"
	@echo "Notarization stapled"

# Create final signed DMG
dist: app-bundle sign notarize dmg
	@echo "Distribution package created!"

# LaunchDaemon management (runs at system boot, as root)
launchdaemon-install:
	@echo "Installing LaunchDaemon for boot-time startup..."
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@sudo $(INSTALLER_DIR)/scripts/launchdaemon.sh install

launchdaemon-uninstall:
	@echo "Uninstalling LaunchDaemon..."
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@sudo $(INSTALLER_DIR)/scripts/launchdaemon.sh uninstall

launchdaemon-start:
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@sudo $(INSTALLER_DIR)/scripts/launchdaemon.sh start

launchdaemon-stop:
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@sudo $(INSTALLER_DIR)/scripts/launchdaemon.sh stop

launchdaemon-status:
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@$(INSTALLER_DIR)/scripts/launchdaemon.sh status

launchdaemon-logs:
	@chmod +x $(INSTALLER_DIR)/scripts/launchdaemon.sh
	@$(INSTALLER_DIR)/scripts/launchdaemon.sh logs