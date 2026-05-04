# Feature Plan: Ephemeral Port Support with Port File

## Context

Currently, the exporter requires a fixed port (default `:8080`). This is problematic for scenarios where:
- Multiple instances may run on the same machine
- Port conflicts with other services occur
- Users want to dynamically assign ports without configuration

## Proposal

Support `:0` as the address value, which binds to a random available port in a configurable range. The assigned port is written to a file, allowing dependent tools (e.g., xbar plugin) to dynamically discover the port.

---

## Design

### 1. New Flags / Environment Variables

| Flag | Env Var | Default | Description |
|------|---------|---------|-------------|
| `-addr` | `EXPORTER_ADDR` | `:8080` | HTTP server address (supports `:0` for ephemeral) |
| `-port-file` | `EXPORTER_PORT_FILE` | `~/.macos-power-consumption-exporter-port-file` | Path to file containing bound port |
| `-port-range-start` | `EXPORTER_PORT_RANGE_START` | `8000` | Start of port range for ephemeral binding |
| `-port-range-end` | `EXPORTER_PORT_RANGE_END` | `9000` | End of port range for ephemeral binding |

### 2. Behavior

1. **If addr is `:0`:**
   - Iterate ports from `port-range-start` to `port-range-end`
   - Attempt to `listen` on each port
   - First available port wins
   - Write port number (as string) to `port-file`
   - If no port available, return error and exit

2. **If addr is anything else (e.g., `:8080`):**
   - Use as-is, do NOT write to port-file (or write if already using ephemeral)

3. **Port file:**
   - Created with `0600` permissions (owner read/write only)
   - Contains only the port number as a string, e.g., `8421`
   - Overwritten on each startup

### 3. Code Changes

#### `cmd/main.go`
- Add new flag variables
- Wire through to exporter

#### `internal/power_usage_exporter/exporter.go`
- Add `PortFile`, `PortRangeStart`, `PortRangeEnd` fields to `Config`
- Add ephemeral port selection logic in `Start()` method
- Write port to file after successful bind
- Handle cleanup: remove file on graceful shutdown

#### `internal/power_usage_reader/reader.go`
- No changes needed

### 4. xbar Plugin Updates

Update `installer/xbar/power-metrics-simple.sh` and `power-metrics.sh`:

```bash
# Read port from env or default file
: "${EXPORTER_PORT_FILE:=$HOME/.macos-power-consumption-exporter-port-file}"
PORT="${EXPORTER_PORT:-$(cat "$EXPORTER_PORT_FILE" 2>/dev/null)}"
PORT="${PORT:-8080}"  # fallback

curl -s "http://localhost:${PORT}/metrics" ...
```

Add documentation for configuring via `.bashrc`/`.zshrc`:

```bash
# .bashrc / .bash_profile / .zshrc

# Export the port file location
export EXPORTER_PORT_FILE="$HOME/.macos-power-consumption-exporter-port-file"

# Optionally: if running via LaunchDaemon, set the env var in the plist
# Or source from /etc/launchd.conf or ~/.launchd.conf
```

### 5. LaunchDaemon plist Update

Add `EnvironmentVariables` to the plist template:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>EXPORTER_PORT_FILE</key>
    <string>/Users/username/.macos-power-consumption-exporter-port-file</string>
</dict>
```

### 6. Documentation Examples

#### Example 1: Running with ephemeral port (shell)

```bash
# Start exporter with ephemeral port
sudo EXPORTER_PORT_FILE=$HOME/.macos-power-exporter-port.txt \
  ./macos-power-consumption-exporter -addr :0

# In another terminal, read the assigned port
cat ~/.macos-exporter-port.txt
# Output: 8421
```

#### Example 2: xbar plugin env config

In `~/.zshrc` (or `~/.bashrc`):

```bash
# Set the port file location for xbar plugins
export EXPORTER_PORT_FILE="$HOME/.macos-power-consumption-exporter-port-file"
```

The xbar plugin will automatically read this file to find the port.

#### Example 3: LaunchDaemon with ephemeral port

In the plist file (`com.combust.macos-power-consumption-exporter.plist`):

```xml
<dict>
    <key>Label</key>
    <string>com.combust.macos-power-consumption-exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/MacOS Power Consumption Exporter.app/Contents/MacOS/macos-power-consumption-exporter</string>
        <string>-addr</string>
        <string>:0</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>EXPORTER_PORT_FILE</key>
        <string>/Users/YOUR_USERNAME/.macos-power-consumption-exporter-port-file</string>
        <key>EXPORTER_PORT_RANGE_START</key>
        <string>8000</string>
        <key>EXPORTER_PORT_RANGE_END</key>
        <string>9000</string>
    </dict>
    ...
</dict>
```

### 7. Error Handling

| Scenario | Behavior |
|----------|----------|
| No free ports in range | Log error, exit with code 1 |
| Cannot write port file | Log error, exit with code 1 |
| Port file deleted while running | Continue running (file is for discovery only) |
| xbar reads empty/missing port file | Fall back to default port 8080 |

---

## Files to Modify

1. `cmd/main.go` - Add new flags
2. `internal/power_usage_exporter/exporter.go` - Ephemeral port logic
3. `installer/xbar/power-metrics-simple.sh` - Read from port file
4. `installer/xbar/power-metrics.sh` - Read from port file
5. `installer/launchdaemon/com.combust.macos-power-consumption-exporter.plist` - Add env vars template
6. `README.md` - Document new flags, env vars, and examples
7. `Makefile` - Possibly add `launchdaemon-install` env var support

---

## Testing Plan

1. **Unit test:** Ephemeral port selection finds available port
2. **Unit test:** Port file is written correctly
3. **Integration test:** Exporter starts with `:0` and xbar reads correct port
4. **Integration test:** Graceful shutdown removes port file

---

## Migration / Backwards Compatibility

- Default behavior unchanged (`:8080` if not specified)
- Port file is only written when using `:0`
- Existing installations continue to work without changes

---

## Implementation Checklist

### Phase 1: Core Exporter Changes

- [x] **1.1. Update `cmd/main.go`** ✅
  - [x] Add `-port-file` flag variable
  - [x] Add `-port-range-start` flag variable
  - [x] Add `-port-range-end` flag variable
  - [x] Read `EXPORTER_PORT_FILE` env var as default
  - [x] Read `EXPORTER_PORT_RANGE_START` env var as default
  - [x] Read `EXPORTER_PORT_RANGE_END` env var as default
  - [x] Pass new config fields to exporter

- [x] **1.2. Update `internal/power_usage_exporter/exporter.go`** ✅
  - [x] Add `PortFile`, `PortRangeStart`, `PortRangeEnd` fields to `Config` struct
  - [x] Implement `findAvailablePort(start, end int) (int, error)` helper function
  - [x] Modify `Start()` to detect `:0` addr and use ephemeral port logic
  - [x] Implement `writePortFile(port int) error` helper
  - [x] Implement `removePortFile() error` helper
  - [x] Call `writePortFile` after successful port bind
  - [x] Register `removePortFile` on graceful shutdown
  - [x] Set `0600` permissions on port file

- [x] **1.3. Add unit tests** ✅
  - [x] Write test for `findAvailablePort` with mocked socket
  - [x] Write test for `writePortFile` correctness
  - [x] Write test for `writePortFile` permission bits
  - [x] Write test for port file cleanup on shutdown

### Phase 2: xbar Plugin Updates

- [x] **2.1. Update `installer/xbar/power-metrics-simple.sh`** ✅
  - [x] Add env var fallback: `: "${EXPORTER_PORT_FILE:=$HOME/.macos-power-consumption-exporter-port-file}"`
  - [x] Add `cat "$EXPORTER_PORT_FILE" 2>/dev/null` as port source
  - [x] Add fallback chain: `PORT="${EXPORTER_PORT:-$(cat "$EXPORTER_PORT_FILE" 2>/dev/null):-8080}"`

- [x] **2.2. Update `installer/xbar/power-metrics.sh`** ✅
  - [x] Apply same changes as 2.1

### Phase 3: LaunchDaemon Updates

- [x] **3.1. Update LaunchDaemon plist template** ✅
  - [x] Locate plist template in `installer/templates/`
  - [x] Add `EnvironmentVariables` dict with `EXPORTER_PORT_FILE` and port range keys
  - [x] Document port range env vars in comments

### Phase 4: Documentation

- [x] **4.1. Update `README.md`** ✅
  - [x] Add new flags table (port-file, port-range-start, port-range-end)
  - [x] Add new environment variables table
  - [x] Add example: Running with ephemeral port
  - [x] Add section: "Shell Configuration for xbar" (.bashrc/.zshrc examples)
  - [x] Update LaunchDaemon section with env var examples
  - [x] Add troubleshooting entry for "port file missing"

- [x] **4.2. Update `Makefile`** ✅
  - [x] Ensure `launchdaemon-install` mentions ephemeral port support

### Phase 5: Integration Testing

- [ ] **5.1. Test ephemeral port binding**
  - [ ] Run exporter with `-addr :0`
  - [ ] Verify port file is created
  - [ ] Verify port is in configured range
  - [ ] Verify metrics endpoint accessible at assigned port

- [ ] **5.2. Test xbar plugin integration**
  - [ ] Set `EXPORTER_PORT_FILE` in environment
  - [ ] Run exporter with `-addr :0`
  - [ ] Verify xbar plugin reads correct port

- [ ] **5.3. Test graceful shutdown**
  - [ ] Run exporter with `-addr :0`
  - [ ] Send SIGTERM
  - [ ] Verify port file is removed

- [ ] **5.4. Test error case: no ports available**
  - [ ] Set port range to very narrow (e.g., single port)
  - [ ] Occupy that port externally
  - [ ] Run exporter with `-addr :0`
  - [ ] Verify error message and non-zero exit

### Phase 6: Code Review & Merge

- [ ] **6.1. Self-review changes**
  - [ ] Verify all new code follows existing patterns
  - [ ] Check error handling coverage
  - [ ] Ensure no sensitive data in logs

- [ ] **6.2. Run full test suite**
  - [ ] `make test` passes
  - [ ] No race conditions in new code

- [ ] **6.3. Merge to main branch**
  - [ ] Create pull request
  - [ ] Address review feedback
  - [ ] Squash and merge