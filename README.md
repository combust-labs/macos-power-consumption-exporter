# macOS power usage prometheus exporter

This program exports the power usage of your macOS device as Prometheus metrics.

The program requires `sudo` permissions because it uses `powermetrics` command to access the power usage data.

## Components

This program contains a number of components:

1. `power_usage_reader` - the component responsible for reading power metrics from the operating system. It does this using the following command: `powermetrics | grep -e "Power:" -e "Combined Power"`. This command produces output continuously until terminated with `CTRL+C`, every iteration produces following lines:

```
CPU Power: 1996 mW
GPU Power: 324 mW
ANE Power: 0 mW
Combined Power (CPU + GPU + ANE): 2320 mW
GPU Power: 324 mW
```

The reader parses this output and outputs the following metrics:

- `power_usage_reader_cpu_power` - the CPU power usage in milliwatts,
- `power_usage_reader_gpu` - the GPU power usage in milliwatts,
- `power_usage_ane_power` - the Apple Neural Engine power usage in milliwatts,
- `power_usage_combined_power` - the combined power usage in milliwatts.

The second occurrence of the `GPU Power` line can be ignored.

The reader records the samples every time it receives the data using a programming-language-specific
 prometheus metric registry. Metrics capture details like hostname, timestamp, etc.

2. `power_usage_exporter` - this component exposes the metrics to the Prometheus server. It is a simple HTTP server that serves the metrics at `/metrics` endpoint.

## This implementation

This version is implemented in Go 1.26.1 programming language. The module is called `github.com/combust-labs/macos-power-consumption-exporter` The program starts both components in the correct order: the reader first, then the exporter. If the reader fails, the program attempts automatic reader component restart. Whenever this happens, the `power_usage_reader_restart_count` metric is incremented.

All components are covered by unit and integration tests.
