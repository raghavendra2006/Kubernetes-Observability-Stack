package main

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ---------- Prometheus Metrics ----------

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests processed, partitioned by method, path, and status code.",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Histogram of response latency (seconds) for HTTP requests.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	httpErrorsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_errors_total",
			Help: "Total number of HTTP errors (5xx responses).",
		},
		[]string{"method", "path"},
	)

	appInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "app_info",
			Help: "Application metadata information.",
		},
		[]string{"version", "go_version"},
	)

	activeConnections = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "http_active_connections",
			Help: "Number of currently active HTTP connections.",
		},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(httpErrorsTotal)
	prometheus.MustRegister(appInfo)
	prometheus.MustRegister(activeConnections)

	// Set application info
	appInfo.WithLabelValues("1.0.0", "1.22").Set(1)
}

// ---------- Middleware ----------

func instrumentHandler(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		activeConnections.Inc()
		defer activeConnections.Dec()

		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next(sw, r)
		duration := time.Since(start).Seconds()

		statusStr := fmt.Sprintf("%d", sw.status)
		httpRequestsTotal.WithLabelValues(r.Method, path, statusStr).Inc()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(duration)

		if sw.status >= 500 {
			httpErrorsTotal.WithLabelValues(r.Method, path).Inc()
		}

		log.Printf("method=%s path=%s status=%d duration=%.4fs",
			r.Method, path, sw.status, duration)
	}
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

// ---------- Handlers ----------

func handleRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"message": "Hello, Observability!", "version": "1.0.0", "timestamp": "%s"}`,
		time.Now().UTC().Format(time.RFC3339))
}

func handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"status": "healthy"}`)
}

func handleReadyz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"status": "ready"}`)
}

func handleError(w http.ResponseWriter, r *http.Request) {
	log.Println("ERROR: Simulated internal server error triggered via /error endpoint")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	fmt.Fprint(w, `{"error": "simulated internal server error", "code": 500}`)
}

func handleSlow(w http.ResponseWriter, r *http.Request) {
	// Simulate a slow response between 2-5 seconds
	delay := time.Duration(2000+rand.Intn(3000)) * time.Millisecond
	log.Printf("WARN: Slow endpoint called, delaying response by %v", delay)
	time.Sleep(delay)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"message": "slow response completed", "delay_ms": %d}`, delay.Milliseconds())
}

func handlePanic(w http.ResponseWriter, r *http.Request) {
	log.Println("CRITICAL: Panic endpoint triggered — this will crash the container if not recovered")
	// This endpoint can be used to test CrashLoopBackOff alerts
	os.Exit(1)
}

// ---------- Main ----------

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	// Application endpoints (instrumented)
	mux.HandleFunc("/", instrumentHandler("/", handleRoot))
	mux.HandleFunc("/healthz", instrumentHandler("/healthz", handleHealthz))
	mux.HandleFunc("/readyz", instrumentHandler("/readyz", handleReadyz))
	mux.HandleFunc("/error", instrumentHandler("/error", handleError))
	mux.HandleFunc("/slow", instrumentHandler("/slow", handleSlow))
	mux.HandleFunc("/panic", instrumentHandler("/panic", handlePanic))

	// Prometheus metrics endpoint (not instrumented to avoid recursion)
	mux.Handle("/metrics", promhttp.Handler())

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("INFO: Sample observability app starting on port %s", port)
	log.Printf("INFO: Endpoints: / /healthz /readyz /error /slow /panic /metrics")

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("FATAL: Server failed to start: %v", err)
	}
}
