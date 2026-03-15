package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// CPU Power in milliwatts
	CPUPower = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "power_usage_reader_cpu_power",
		Help: "CPU power usage in milliwatts",
	}, []string{"hostname"})

	// GPU Power in milliwatts
	GPUPower = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "power_usage_reader_gpu_power",
		Help: "GPU power usage in milliwatts",
	}, []string{"hostname"})

	// ANE Power in milliwatts
	ANEPower = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "power_usage_ane_power",
		Help: "Apple Neural Engine power usage in milliwatts",
	}, []string{"hostname"})

	// Combined Power in milliwatts
	CombinedPower = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "power_usage_combined_power",
		Help: "Combined power usage (CPU + GPU + ANE) in milliwatts",
	}, []string{"hostname"})

	// Reader restart count
	ReaderRestartCount = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "power_usage_reader_restart_count",
		Help: "Number of times the reader component has been restarted",
	}, []string{"hostname"})
)