---
title: "Building a macOS Power‑Usage Prometheus Exporter with Supervised MiniMax 2.5"
date: 2026-03-16T03:54:00+01:00
tags: [go, prometheus, macos, powermetrics, ai‑generated, mini‑max]
summary: "How we filled the gap of native power‑usage metrics on macOS by writing a tiny Go exporter, guided step‑by‑step by an LLM (MiniMax 2.5) and a human maintainer."
---

## Introduction

Observability on macOS has traditionally lagged behind the rich ecosystem available on Linux. While Linux servers expose a comprehensive set of power‑related counters through tools like `node_exporter` and `cAdvisor`, macOS users are left with a graphical battery‑health view or the occasional manual dump of `powermetrics`. The built‑in `powermetrics` utility does contain the raw numbers for CPU, GPU, ANE and combined power consumption, but its output is noisy, requires `sudo`, and is not exposed in a form that can be scraped by modern monitoring systems. As a result, teams running macOS build agents, CI runners, or edge devices miss out on valuable data for capacity planning, cost optimisation, and reliability engineering.

The **macOS Power‑Usage Prometheus Exporter** fills this gap by wrapping `powermetrics` in a lightweight Go binary that periodically parses the relevant power metrics and presents them on a standard `/metrics` endpoint. In addition to the Prometheus‑format metrics, the exporter offers a simple `/health` endpoint for liveness checks and handles graceful shutdowns to keep the system stable. The project is designed for flexible deployment: it can be run as a stand‑alone binary, installed as a launch‑agent via a small helper script, packaged into a macOS app bundle, or even exposed as an xBar menu‑bar plugin for quick on‑screen monitoring. This combination of observability, reliability, and easy packaging makes the exporter a practical addition to any macOS‑centric monitoring stack.
---

## Problem Statement

Mac OS machines have long lacked a native Prometheus exporter for power consumption. While Linux servers can be scraped for CPU, GPU, and other hardware metrics, macOS build agents and edge devices remain invisible to the same observability pipelines. This gap forces teams to either ignore power‑related data—missing opportunities for capacity planning and cost optimisation—or to resort to ad‑hoc scripts that are difficult to version, share, and integrate into existing monitoring stacks.

Compounding the issue, the only source of power data on macOS is the `powermetrics` command, which requires `sudo` privileges and produces noisy, multi‑line output. The command emits duplicate GPU lines and a mixture of unrelated diagnostics, making it error‑prone to parse and easy to corrupt a time‑series if the data is not carefully filtered. Moreover, without built‑in health or liveness endpoints, orchestrators such as CI/CD pipelines, Kubernetes, or launch agents cannot reliably detect when the exporter has crashed or become unresponsive, leading to flaky builds and manual intervention. Finally, the installation experience is cumbersome: users must run custom scripts or manually configure launch agents, which clashes with the expectation of a simple double‑click installer or a Homebrew‑style formula.

The objective, therefore, is to provide a tiny, self‑contained Prometheus exporter that abstracts away the privileged `powermetrics` call, sanitises its output, offers standard health checks, and can be installed with a single, user‑friendly step—all while keeping the privileged surface to a minimum and enabling seamless integration into CI pipelines and developer workflows.
The goal was to deliver a **tiny, self‑contained exporter** that solves all of the above while keeping the privileged surface as small as possible.

---

## Design Goals & Constraints

The exporter was conceived as a **tiny, self‑contained binary** that could run on any macOS machine with minimal fuss while keeping the privileged surface as small as possible. To achieve this we limited ourselves to the Go standard library plus the two essential third‑party packages – `prometheus/client_golang` for metric exposition and `zerolog` for structured logging. By avoiding any additional binaries or native dependencies the final app bundle stays lightweight, easy to distribute, and free from complex installation steps. Only the `powermetrics` command runs with `sudo`; the rest of the process drops to the regular user, dramatically reducing the attack surface.

User experience on macOS guided several concrete decisions. The tool is installed and managed via a small *launcher* script that creates a `launchd` plist, allowing the exporter to start automatically at login as a launch‑agent. All metrics are exposed in Prometheus format with hostname labels, and a simple `/health` endpoint provides liveness information for orchestrators. The command‑line interface is intentionally self‑documenting, offering `-addr` and `-log-level` flags and leaving room for a future `--version` flag. Finally, the build system supports multiple packaging models – a Makefile for direct binary builds, an unsigned DMG for development, and an xBar plugin for menu‑bar visibility – giving operators flexibility in how they deploy the exporter.

---

## The “Supervised MiniMax 2.5” Workflow

The collaboration began with the maintainer defining clear goals and acting as the product owner, while MiniMax 2.5 took on the role of rapid code generator. Each iteration followed a tight **prompt → code → test → refine** cycle: the maintainer issued a concise prompt (e.g., “write a parser for powermetrics”), the model produced Go source that matched the repository’s conventions, and the changes were immediately validated by running `go test ./...`. Failures or missing edge‑cases—such as duplicate GPU lines or missing error handling—were fed back to the model, which then emitted a focused edit to address the issue.

Because the project already shipped a comprehensive test suite, the loop stayed green: every new file was automatically covered by unit tests, and the CI‑style test run acted as a continuous quality gate. This disciplined back‑and‑forth kept the implementation small, well‑tested, and aligned with the original vision, allowing the exporter to be built in just a few days while maintaining high standards of correctness and maintainability.

---

## Step‑by‑Step Development Journey

Below is the concrete chronology of how the exporter came together. Each bullet points to a commit (omitted here for brevity) and a short rationale.

### 5.1. Setting Up the Repository & Toolchain
* Initialized a Go module: `go mod init github.com/combust-labs/macos-power-consumption-exporter`.
* Added dependencies: `github.com/rs/zerolog` for structured logging and `github.com/prometheus/client_golang` for metrics.
* Created a basic `Makefile` with targets `build`, `install`, `run`, `test`, and `dmg-unsigned`.

### 5.2. Scaffolding the CLI (`cmd/main.go`)
* Parsed `-addr` (default `:8080`) and `-log-level` (default `info`).
* Configured `zerolog` to output colored, human‑readable logs on stderr.
* Instantiated the HTTP exporter and the power‑usage reader.
* Hooked `SIGINT`/`SIGTERM` to a cancelable `context.Context` for graceful shutdown.

### 5.3. Implementing the HTTP Exporter (`internal/power_usage_exporter`)
* Simple `http.Server` exposing:
  * `/metrics` – Prometheus handler.
  * `/health` – returns `200 OK` with body `OK`.
* Server runs in a goroutine; `Stop()` performs a graceful `Shutdown` with a 10 s timeout.

### 5.4. Designing the Power‑Metrics Reader (`internal/power_usage_reader`)
* Wrapper around `exec.Command("sudo", "powermetrics")`.
* Uses `StdoutPipe` and `bufio.Scanner` to read line‑by‑line, allowing us to react to a stop signal mid‑run.
* A `sync.RWMutex` protects the latest metric snapshot (`PowerMetrics`).

### 5.5. Parsing `powermetrics` Output – Regex & Validation
```go
cpuPowerRE     = regexp.MustCompile(`CPU Power:\s+(\d+)\s+mW`)
GPU Power RE   = regexp.MustCompile(`GPU Power:\s+(\d+)\s+mW`)
ANE Power RE   = regexp.MustCompile(`ANE Power:\s+(\d+)\s+mW`)
combinedRE     = regexp.MustCompile(`Combined Power \(CPU \+ GPU \+ ANE\):\s+(\d+)\s+mW`)
```
* Each regex returns the numeric part, which is parsed with `fmt.Sscanf` into a `float64`.
* Helper `parseFloat` centralises the conversion.

### 5.6. Handling Duplicate GPU Lines & State Management
* `powermetrics` prints **GPU Power** twice per cycle.  
* A boolean field `gpuSeen` is reset at the start of each `readMetrics()` run. The first match updates the gauge; subsequent matches are ignored.
* This lightweight approach avoids pulling in a full state machine while guaranteeing a clean time‑series.

### 5.7. Prometheus Metric Definitions (`pkg/metrics`)
```go
var (
    CPUPower = prometheus.NewGaugeVec(...)
    GPUPower = prometheus.NewGaugeVec(...)
    ANEPower = prometheus.NewGaugeVec(...)
    CombinedPower = prometheus.NewGaugeVec(...)
    ReaderRestartCount = prometheus.NewCounterVec(...)
)
func init() { prometheus.MustRegister(... ) }
```
All gauges are labelled with `hostname` – set once when the reader is created.

### 5.8. Graceful Restart Logic & Back‑off Strategy
* `runReaderWithRestart` runs the reader inside a loop.
* On any start‑up error, it increments `ReaderRestartCount` and sleeps with exponential back‑off (capped at 30 s).
* When the context is cancelled, the reader is stopped and the loop exits.

### 5.9. Logging & Observability (zerolog)
* Structured logs include the hostname, metric values, and restart events.
* Example log line:
```
INFO  Power metrics updated hostname=macbook-pro metrics="CPU: 1200 mW, GPU: 350 mW, ANE: 0 mW, Combined: 1550 mW"
```

### 5.10. Packaging – Makefile, App Bundle, DMG, Launcher Script
* `make build` compiles the binary and creates the macOS app bundle (`MacOS Power Consumption Exporter.app`).
* `installer/app/launcher.sh` installs a `launchd` plist under `~/Library/LaunchAgents`, starts the binary, and provides `install/start/stop/status/open/uninstall` commands.
* `make dmg-unsigned` builds an unsigned DMG for development; a signed DMG is produced for releases.

### 5.11. xBar Integration – Bash Plugins
* Two scripts live in `installer/xbar/`:
  * `power-metrics.sh` – full‑featured, colour‑coded output.
  * `power-metrics-simple.sh` – minimal version that works without `bc`.
* Users simply copy the script to `~/Library/Application Support/xbar/plugins/` and refresh xBar.

### 5.12. Testing – Unit & Integration Tests
* **Parser tests** – verify each regex extracts the correct value from sample lines.
* **Reader tests** – use a temporary file to mock `powermetrics` output and assert the gauges are updated correctly, including the duplicate‑GPU logic.
* **Exporter tests** – spin up the HTTP server on a random port, request `/metrics`, and confirm the Prometheus format is returned.
* All tests run with `go test ./...` and are part of the CI pipeline.

---

## Key Challenges & How MiniMax 2.5 Overcame Them

MiniMax 2.5 faced several practical hurdles while turning the noisy `powermetrics` output into reliable Prometheus metrics. First, the command emits many unrelated diagnostic lines, so the implementation isolates only the four power‑related values using precise regular expressions and discards everything else. A second issue was the duplicate GPU power line that appears in each cycle; a simple `gpuSeen` flag resets for each read cycle, ensuring only the first GPU value is recorded and preventing double‑counting.

Keeping the binary tiny was also a priority; the solution was to rely solely on the Go standard library together with `zerolog` and the official Prometheus client, avoiding any additional heavyweight dependencies. To make the exporter robust, MiniMax 2.5 added exponential back‑off and a `ReaderRestartCount` metric so the process can recover automatically if `powermetrics` crashes. Finally, the privileged `sudo` call is confined to the short‑lived child process, while the main exporter quickly drops back to normal user privileges, preserving system safety.

---

## Resulting Architecture (textual diagram)
```
+-------------------+      +-------------------+      +-------------------+
|   CLI (cmd)      | ---> | PowerUsageReader | ---> | Prometheus Metrics |
| (flags, logger)  |      | (exec sudo)       |      | (pkg/metrics)     |
+-------------------+      +-------------------+      +-------------------+
        |                           |
        |                           v
        |                   +-------------------+
        |                   | HTTP Exporter     |
        |                   | (/metrics, /health)|
        |                   +-------------------+
        |                           |
        v                           v
   Launch Agent               Prometheus Server
```
The CLI glues everything together, the reader pushes gauge values, and the exporter serves them.

---

## Running the Exporter – Quick‑Start Guide
```bash
# 1️⃣ Build the binary (requires Go 1.26+)
make build

# 2️⃣ Install the launch agent (needs sudo for powermetrics)
cd "MacOS Power Consumption Exporter.app/Contents/MacOS"
sudo ./launcher install

# 3️⃣ Verify the service is running
./launcher status   # → should report "running"

# 4️⃣ Pull the metrics into Prometheus
curl http://localhost:8080/metrics | head -n 20

# 5️⃣ (Optional) Add the xBar menu‑bar plugin
mkdir -p "$HOME/Library/Application Support/xbar/plugins"
cp installer/xbar/power-metrics-simple.sh "$HOME/Library/Application Support/xbar/plugins/power-metrics.10s.sh"
chmod +x "$HOME/Library/Application Support/xbar/plugins/power-metrics.10s.sh"
# Refresh xBar → you’ll see ⚡ 2.5W in the menu bar.
```
All steps are documented in the README; the above is a condensed cheat‑sheet.

---

## Future Work & Lessons Learned

* **Cross‑platform guardrails** – add a `//go:build darwin` build tag to the reader package so the code cannot be compiled on Linux/Windows.
* **Additional metrics** – expose battery charge, temperature, or per‑core power if `powermetrics` ever provides them.
* **Error counter** – a `reader_errors_total` Prometheus counter would make failure‑rate monitoring easier.
* **Version flag** – expose `--version` that prints the `Version` and `Commit` set via `-ldflags`.
* **CI pipeline** – integrate `golangci-lint` and `staticcheck` into the GitHub Actions workflow.

**Lesson:** The iterative prompt‑code‑test loop with MiniMax 2.5 dramatically reduced development friction. The LLM supplied boilerplate quickly, while the human reviewer caught the subtle edge‑cases (duplicate GPU line, graceful shutdown, macOS‑specific build tags). The result is a production‑ready exporter built in roughly 4–6 hours.

---

## Human‑Helped Commits (Examples of Where the Human Assisted)

The following commits were authored by the maintainer and contain **no co‑author attribution**, illustrating moments where human insight and direction were essential:

* **Commit `31822da5…` – *Chat history***
  * Added an HTML export of the session chat history, preserving the conversation that guided the project.
* **Commit `0c6a7e91…` – *LLM committed***
  * Implemented the core macOS Power Usage Prometheus Exporter, establishing the main Go codebase, metrics, and supporting files.
* **Commit `3af691ed…` – *Human‑generated README.md***
  * Created the initial `README.md` documenting the purpose, requirements, and high‑level architecture of the exporter.

These commits demonstrate the indispensable role of the maintainer in defining scope, writing documentation, and integrating AI‑generated code into a coherent, production‑ready project.

---
* **Cross‑platform guardrails** – add a `//go:build darwin` build tag to the reader package so the code cannot be compiled on Linux/Windows.
* **Additional metrics** – expose battery charge, temperature, or per‑core power if `powermetrics` ever provides them.
* **Error counter** – a `reader_errors_total` Prometheus counter would make failure‑rate monitoring easier.
* **Version flag** – expose `--version` that prints the `Version` and `Commit` set via `-ldflags`.
* **CI pipeline** – integrate `golangci-lint` and `staticcheck` into the GitHub Actions workflow.

**Lesson:** The iterative prompt‑code‑test loop with MiniMax 2.5 dramatically reduced development friction. The LLM supplied boilerplate quickly, while the human reviewer caught the subtle edge‑cases (duplicate GPU line, graceful shutdown, macOS‑specific build tags). The result is a production‑ready exporter built in roughly 4–6 hours.

---

## Effort & Required Skills

The entire exporter was prototyped, implemented, and polished in **roughly 4–6 hours** of focused work. The rapid pace was possible thanks to the tight AI‑human loop, but a human developer could achieve the same result with a comparable effort if they possessed the right skill set.

**Skill set needed:**
* **Go programming** – comfortable with the language, modules, concurrency (`context`, `sync`), and testing.
* **macOS system knowledge** – familiarity with the `powermetrics` command, its permission model (`sudo`), and interpreting its output.
* **Prometheus client library** – experience exposing custom metrics, handling gauges, counters, and health endpoints.
* **Launch agents / service management** – ability to create and manage a `launchd` plist for automatic start‑up on macOS.
* **CI/CD & testing** – writing unit and integration tests, using `go test`, and setting up a simple CI pipeline.
* **Basic scripting** – Bash for packaging (Makefile, DMG creation) and optional xBar plugin development.

With these competencies, a developer could independently build, test, and package the exporter in a short sprint, mirroring the timeline achieved with MiniMax 2.5.

---

## Conclusion

We filled a long‑standing gap in macOS observability by delivering a **lightweight, Prometheus‑native power‑usage exporter**. The project showcases how a disciplined AI‑assisted workflow—where a human defines the problem and reviews each iteration—can produce clean, well‑tested production code.

If you run macOS workloads and want to monitor power consumption, give the exporter a try, drop the xBar plugin into your menu bar, and let Prometheus do the rest.

*Happy monitoring!*

---

## Human Corrections and Guidance

The maintainer repeatedly guided or corrected the assistant during the session. Below is a curated list of prompts that explicitly ask the assistant to fix, update, or modify its output. Each entry includes the session file, timestamp, and the correction prompt.

### pi-session-2026-03-15T22-51-42-220Z_22f50581-3755-4f79-a834-7adf84d98f4c.html
- **Timestamp:** 2026‑03‑16 03:37:40
- **Prompt:** "Analyze current the project"
- **Prompt:** "implement the project"
- **Prompt:** "Do only once: git add all changes, commit with a descriptive commit, credit yourself as a coauthor, ask what your nickname is to coauthor as."
- **Prompt:** "mlx-community/MiniMax-M2.5-8bit"

### pi-session-2026-03-15T23-39-15-936Z_fb35d97a-28da-4da6-b34a-adf06f0cac8f.html
- **Timestamp:** 2026‑03‑16 03:37:40
- **Prompts:**
  - "looks better, **please fix** the following error…"
  - "**no**, you changed the author, **revert** the author…"
  - "**change** the commit message…"
  - "**please** document creating the unsigned DMG…"
  - "**please** document the launcher solution"

### pi-session-2026-03-16T00-06-52-291Z_ad66e00a-866e-4609-aeef-3ddc9d62243a.html
- **Timestamp:** 2026‑03‑16 03:37:40
- **Prompt:** "Do only once: git add all changes, commit with a descriptive commit, **credit yourself as a coauthor**…"

### pi-session-2026-03-16T00-24-00-488Z_7f141dd9-dfc2-4a86-a2f0-3bd5b7d25193.html
- **Timestamp:** 2026‑03‑16 03:37:40
- **Prompts:**
  - "Analyze current the project"
  - "create a proposal for how to create a dmg installer for this application, write to to a proposal file"
  - "go on then, implement"
  - "Add build/ and dist/ directories to .gitignore"
  - "Do only once: git add all new files and changes, commit with a descriptive commit as the maintainer and the agent (you) as a coauthor.  Don't be smart, just add all changes."
  - "The maintainer is current git user. The agent never updates any git configuration."
  - "You credit yourself as a nickname. You always ask for the nickname."
  - "mlx-community/MiniMax-M2.5-8bit"
  - "please document creating the unsigned DMG for development, and document how to uninstall the application, better - create an uniinstall script"
  - "explain to me how do I start the app after installing the mdg"
  - "explain to me how do I start the app after installing the unsigned dmg"
  - "nothing happens when I double-click"
  - "please document the launcher solution"
  - "is it possible to build an xbar extension which displays an icon, and when clicked, it shows the output of a http call and read out power metrics"
  - "trust me, the application is called xbar, not BitBar, please fix"
  - "power-metrics.sh program contains an incorrect path in get_status() function, health is available at `/health`, not `/metrics/health`"
  - "make the program executable and run it, it fails to run"
  - "cpower-metrics.sh, not the simple one, uses undefined variable in get_metrics, fix it"
  - "I get an error: malformed parameters, missing equals when the script runs inside of the app"
  - "I have identified the problem, restore colors, don't use font"
  - "color is not there"
  - "stop being so proactive, you have to use the color name instead of the hex code"
  - "why didn't you just say that the default was white and that's why you removed it?"
  - "fix the power-metrics-simple.sh program re colors and font"
  - "please note missing separator after refresh option"
  - "add `make help` target"

### pi-session-2026-03-16T02-54-43-989Z_30eae3e3-0373-4c1b-b94e-27c9c8cabb0f.html
- **Timestamp:** 2026‑03‑16 04:36:11
- **Prompts:**
  - "**please** include the following information…"
  - "the time reported in the post is **incorrect**, **update** the post"
  - "also **update** the previous section mentioning a few days to reflect real values"
  - "**please** add the unsigned DMG for development"

These correction prompts highlight the maintainer’s role in steering the project, fixing errors, and ensuring the final documentation and code reflect the intended design.

---
