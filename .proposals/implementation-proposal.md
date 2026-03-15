# macOS Power Usage Prometheus Exporter - Implementation Proposal

## Project Overview

**Project Name:** macos-power-consumption-exporter  
**Module:** `github.com/combust-labs/macos-power-consumption-exporter`  
**Language:** Go 1.26.1  
**Purpose:** Export macOS power usage metrics for Prometheus monitoring

---

## Implementation Checklist

### Phase 1: Project Setup

- [ ] Initialize Go module with `go mod init github.com/combust-labs/macos-power-consumption-exporter`
- [ ] Create project directory structure:
  ```
  cmd/
    main.go
  internal/
    power_usage_reader/
      reader.go
      reader_test.go
    power_usage_exporter/
      exporter.go
      exporter_test.go
  pkg/
    metrics/
      metrics.go
  go.mod
  go.sum
  ```
- [ ] Set up logging library (e.g., zerolog or zap)
- [ ] Create basic Makefile for building and testing

### Phase 2: Power Usage Reader Component

- [ ] Implement `PowerUsageReader` struct with required fields
- [ ] Create `powermetrics` command executor that runs:
  ```bash
  sudo powermetrics | grep -e "Power:" -e "Combined Power"
  ```
- [ ] Implement output parser for:
  - `CPU Power: <value> mW`
  - `GPU Power: <value> mW`
  - `ANE Power: <value> mW`
  - `Combined Power (CPU + GPU + ANE): <value> mW`
- [ ] Handle the duplicate `GPU Power` line (ignore second occurrence)
- [ ] Integrate with Prometheus metric registry:
  - `power_usage_reader_cpu_power` (Gauge)
  - `power_usage_reader_gpu_power` (Gauge)
  - `power_usage_ane_power` (Gauge)
  - `power_usage_combined_power` (Gauge)
- [ ] Add labels: hostname, timestamp
- [ ] Implement graceful shutdown handling
- [ ] Write unit tests for parser
- [ ] Write integration tests for reader

### Phase 3: Power Usage Exporter Component

- [ ] Implement `PowerUsageExporter` struct
- [ ] Create HTTP server with `/metrics` endpoint
- [ ] Register Prometheus metrics handler
- [ ] Implement graceful shutdown
- [ ] Add health check endpoint (optional: `/health`)
- [ ] Write unit tests for HTTP handlers

### Phase 4: Main Application Integration

- [ ] Create `main.go` that orchestrates both components
- [ ] Start reader component first, then exporter
- [ ] Implement automatic reader restart logic:
  - Monitor reader for failures
  - Increment `power_usage_reader_restart_count` metric on restart
  - Implement backoff strategy for restarts
- [ ] Add signal handling for SIGINT/SIGTERM
- [ ] Configure proper log levels

### Phase 5: Prometheus Metrics Configuration

- [ ] Define metric descriptions:
  - `power_usage_reader_cpu_power` - CPU power in milliwatts
  - `power_usage_reader_gpu_power` - GPU power in milliwatts
  - `power_usage_ane_power` - ANE power in milliwatts
  - `power_usage_combined_power` - Combined power in milliwatts
  - `power_usage_reader_restart_count` - Reader restart counter
- [ ] Add appropriate metric types (Gauge, Counter)
- [ ] Add hostname label to all metrics

### Phase 6: Testing

- [ ] Write unit tests for:
  - Power metrics parser
  - Reader logic
  - Exporter HTTP handlers
- [ ] Write integration tests:
  - Full reader pipeline test
  - Exporter endpoint test
- [ ] Add test coverage reporting
- [ ] Set up CI/CD pipeline (GitHub Actions)

### Phase 7: Documentation & Release

- [ ] Add README with:
  - Installation instructions
  - Usage examples
  - Prometheus configuration example
- [ ] Add code comments and godoc
- [ ] Create Docker configuration (optional)
- [ ] Tag release version

---

## Technical Considerations

### Dependencies (Proposed)
- `github.com/prometheus/client_golang` - Prometheus metrics
- `github.com/prometheus/common` - Common Prometheus utilities
- `github.com/rs/zerolog` - Structured logging
- `github.com/stretchr/testify` - Testing assertions

### Error Handling
- Reader failures should be logged and trigger automatic restart
- Exporter HTTP errors should return proper status codes
- All errors should be logged with context

### Performance
- Use buffered channels for reader → exporter communication
- Limit metric collection frequency to avoid excessive CPU usage
- Consider using sync.Map for thread-safe metric updates

### Security
- Document sudo requirements clearly
- Consider using systemd service with proper privileges
- Validate all parsed input from powermetrics

---

## Acceptance Criteria

1. ✅ Program compiles without errors on macOS
2. ✅ `powermetrics` output is correctly parsed
3. ✅ All four power metrics are exposed at `/metrics`
4. ✅ Reader automatically restarts on failure
5. ✅ Restart counter metric is incremented on each restart
6. ✅ Unit tests pass for core components
7. ✅ Integration tests verify end-to-end functionality
8. ✅ Program handles graceful shutdown

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1: Project Setup | 1-2 hours |
| Phase 2: Power Usage Reader | 4-6 hours |
| Phase 3: Power Usage Exporter | 2-3 hours |
| Phase 4: Main Application | 2-3 hours |
| Phase 5: Prometheus Metrics | 1-2 hours |
| Phase 6: Testing | 3-4 hours |
| Phase 7: Documentation | 1-2 hours |

**Total Estimated Time:** 14-22 hours