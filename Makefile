.PHONY: build test clean install run help

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

# Go build variables
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS=-ldflags "-X main.Version=$(VERSION) -X main.Commit=$(COMMIT)"

# Default target
help:
	@echo "Available targets:"
	@echo "  build    - Build the binary"
	@echo "  test     - Run tests"
	@echo "  clean    - Clean build artifacts"
	@echo "  install  - Install dependencies"
	@echo "  run      - Run the application"
	@echo "  help     - Show this help message"

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