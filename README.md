# 🔭 Kubernetes Observability Stack

A **production-grade** observability platform for Kubernetes integrating **Prometheus** (metrics), **Loki** (logs), **Promtail** (log collection), **Grafana** (visualization), and **Alertmanager** (alerting) — deployed entirely via declarative Helm charts and Kubernetes manifests.

---

## 📐 Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                          │
│                                                                     │
│  ┌─────────────────────── monitoring namespace ──────────────────┐  │
│  │                                                               │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │  │
│  │  │  Prometheus   │    │ Alertmanager │    │   Grafana    │    │  │
│  │  │   Operator    │    │   + PVC 5Gi  │    │  + PVC 10Gi  │    │  │
│  │  └──────┬───────┘    └──────▲───────┘    └──┬───────┬───┘    │  │
│  │         │ manages           │ alerts         │query  │query   │  │
│  │  ┌──────▼───────┐           │          ┌─────▼──┐ ┌──▼─────┐ │  │
│  │  │  Prometheus  ├───────────┘          │ Prom   │ │  Loki  │ │  │
│  │  │  + PVC 50Gi  │                     │  DS    │ │  DS    │ │  │
│  │  └──────┬───────┘                     └────────┘ └──▲─────┘ │  │
│  │         │ scrape                                     │ push   │  │
│  │  ┌──────▼───────┐    ┌──────────────┐    ┌──────────┴─────┐  │  │
│  │  │ServiceMonitor│    │   Webhook    │    │   Promtail     │  │  │
│  │  │    CRDs      │    │  Receiver    │    │  (DaemonSet)   │  │  │
│  │  └──────┬───────┘    └──────────────┘    └──────────┬─────┘  │  │
│  └─────────┼────────────────────────────────────────────┼────────┘  │
│            │ discover                          collect  │           │
│  ┌─────────▼──────────── sample-app namespace ──────────▼────────┐  │
│  │  ┌──────────────┐    ┌──────────────┐                        │  │
│  │  │  Sample App  │    │  Sample App  │  (2 replicas)          │  │
│  │  │  /metrics    │    │  /metrics    │  Go HTTP + Prometheus  │  │
│  │  └──────────────┘    └──────────────┘                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

| Flow | Path | Protocol |
|------|------|----------|
| **Metrics** | Sample App `/metrics` → Prometheus (ServiceMonitor) → Grafana (PromQL) | HTTP pull |
| **Logs** | Pod stdout → Promtail (DaemonSet) → Loki → Grafana (LogQL) | HTTP push |
| **Alerts** | PrometheusRule → Prometheus → Alertmanager → Webhook Receiver | HTTP push |
| **Correlation** | Shared labels (`namespace`, `pod`, `container`) across Prometheus + Loki | Data links |

---

## 🛠️ Technology Stack

| Component | Purpose | Chart/Image |
|-----------|---------|-------------|
| **Prometheus Operator** | Manages Prometheus lifecycle via CRDs | `prometheus-community/kube-prometheus-stack` |
| **Prometheus** | Metrics collection & storage (50Gi PVC, 15d retention) | Bundled with operator |
| **Alertmanager** | Alert routing & notification (5Gi PVC) | Bundled with operator |
| **Grafana** | Visualization & dashboarding (10Gi PVC) | Bundled with operator |
| **Loki** | Log aggregation & storage (20Gi PVC, 7d retention) | `grafana/loki` |
| **Promtail** | Log collection DaemonSet with K8s metadata | `grafana/promtail` |
| **kube-state-metrics** | Kubernetes object metrics | Bundled with operator |
| **node-exporter** | Node-level hardware/OS metrics | Bundled with operator |
| **Sample App** | Go HTTP server with Prometheus instrumentation | Custom (see `sample-app/`) |
| **Webhook Receiver** | Mock Alertmanager notification target | Python inline |

---

## 📋 Prerequisites

- **Kubernetes cluster** (v1.25+) — Minikube, Kind, Docker Desktop, GKE, EKS, or AKS
- **kubectl** (v1.25+) — configured to connect to your cluster
- **Helm** (v3.12+) — Kubernetes package manager
- **Docker** (optional) — for building the sample app image locally

### Quick Setup with Minikube

```bash
# Install Minikube (if not already installed)
# macOS: brew install minikube
# Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Start a cluster with sufficient resources
minikube start --cpus=4 --memory=8192 --disk-size=40g

# Verify
kubectl cluster-info
```

---

## 🚀 Deployment

### Option A: Automated (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-username/Kubernetes-Observability-Stack.git
cd Kubernetes-Observability-Stack

# Build the sample app image (if using Minikube)
eval $(minikube docker-env)
docker build -t sample-observability-app:latest ./sample-app

# Deploy everything
chmod +x scripts/*.sh
./scripts/deploy.sh
```

### Option B: Step-by-Step Manual Deployment

```bash
# 1. Create namespaces
kubectl apply -f kubernetes/namespace.yaml

# 2. Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 3. Deploy kube-prometheus-stack (Prometheus + Alertmanager + Grafana)
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm-values/kube-prometheus-stack.yaml \
  --wait --timeout 10m

# 4. Deploy Loki
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values helm-values/loki.yaml \
  --wait --timeout 10m

# 5. Deploy Promtail
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --values helm-values/promtail.yaml \
  --wait --timeout 5m

# 6. Deploy supporting components
kubectl apply -f kubernetes/webhook-receiver/
kubectl apply -f kubernetes/sample-app/
kubectl apply -f kubernetes/alerting/

# 7. Create Grafana dashboard ConfigMap
kubectl create configmap grafana-custom-dashboards \
  --from-file=grafana-dashboards/kubernetes-cluster-overview.json \
  --from-file=grafana-dashboards/application-performance.json \
  --namespace monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap grafana-custom-dashboards \
  grafana_dashboard=1 --namespace monitoring --overwrite

# 8. Verify pods
kubectl get pods -n monitoring
kubectl get pods -n sample-app
```

---

## 🔗 Accessing the UIs

Run these port-forward commands in separate terminals:

```bash
# Grafana (main dashboard)
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# → http://localhost:3000  |  admin / observability-admin

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# → http://localhost:9090

# Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
# → http://localhost:9093

# Sample Application
kubectl port-forward svc/sample-app 8080:8080 -n sample-app
# → http://localhost:8080          (app)
# → http://localhost:8080/metrics  (Prometheus metrics)
```

---

## 📊 Grafana Dashboards

### 1. Kubernetes Cluster Overview (`/d/k8s-cluster-overview`)

| Row | Panels | Data Source |
|-----|--------|-------------|
| **Cluster Summary** | Total Nodes, Running Pods, Failed Pods, Namespaces, CPU %, Memory % | Prometheus |
| **Node Metrics** | CPU usage per node, Memory usage per node, Network I/O, Disk I/O | Prometheus |
| **Pod Metrics** | Pod status distribution (pie chart), Pod restart counts (table) | Prometheus |
| **Container Resources** | CPU usage by namespace, Memory usage by namespace | Prometheus |
| **Cluster Logs** | Live log stream filtered by namespace and search keyword | Loki |

### 2. Application Performance (`/d/app-performance`)

| Row | Panels | Data Source |
|-----|--------|-------------|
| **RED Metrics** | Request Rate (req/s), Error Rate (%), Average Latency (p50) | Prometheus |
| **Request Details** | Rate by HTTP status code (stacked), Latency percentiles (p50/p90/p99) | Prometheus |
| **Error Analysis** | Error rate gauge, Error rate by path, Request throughput by path | Prometheus |
| **Application Logs** | Correlated log stream filtered by namespace, pod, and keyword | Loki |
| **Resource Consumption** | CPU usage vs request vs limit, Memory usage vs request vs limit | Prometheus |

### Metrics-to-Logs Correlation

The dashboards implement correlation through:

1. **Shared template variables** — `$namespace`, `$pod` variables are used in both PromQL and LogQL queries
2. **Data links** — Click any time series panel → "View Logs in Loki" opens Explore with the exact time range and pod filters pre-populated
3. **Side-by-side panels** — Metric panels sit directly above the Loki logs panel for visual correlation
4. **Consistent labels** — Promtail enriches logs with the same `namespace`, `pod`, `container` labels used by Prometheus

**To test correlation:**
1. Open the Application Performance dashboard
2. Generate some error traffic: `curl http://localhost:8080/error` (repeat several times)
3. Observe the error rate spike in the "Request Rate by Status Code" panel
4. Click the spike → select "View Logs in Loki"
5. The Explore view opens with `{namespace="sample-app"}` and the correct time range
6. You should see the `ERROR: Simulated internal server error` log lines

---

## 🚨 Alerting

### Defined Alert Rules

| Alert | Expression | Severity | For | Trigger |
|-------|-----------|----------|-----|---------|
| **HighCPUUsage** | Container CPU > 80% of limit | ⚠️ Warning | 5m | CPU stress pod |
| **PodCrashLooping** | Pod in CrashLoopBackOff state | 🔴 Critical | 5m | Crashing pod |
| **HighApplicationErrorRate** | HTTP 5xx rate > 5% of total | 🔴 Critical | 2m | `/error` endpoint |
| **PrometheusTargetDown** | Scrape target unreachable | ⚠️ Warning | 5m | Delete sample app |
| **HighMemoryUsage** | Container memory > 85% of limit | ⚠️ Warning | 5m | Memory pressure |

### Alert Routing

```
Prometheus → Alertmanager → Webhook Receiver (logs to stdout)
                │
                ├── Critical: group_wait=10s, repeat=1h
                └── Warning:  group_wait=1m,  repeat=4h
```

### Testing Alerts

```bash
# Run all alert tests
./scripts/test-alerts.sh

# Or test individually
./scripts/test-alerts.sh errors     # High error rate
./scripts/test-alerts.sh crashloop  # CrashLoopBackOff
./scripts/test-alerts.sh cpu        # High CPU

# Verify alerts fired
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# → http://localhost:9090/alerts

# Check webhook receiver logs
kubectl logs -l app=alertmanager-webhook-receiver -n monitoring --tail=50

# Clean up test resources
./scripts/test-alerts.sh cleanup
```

---

## 📁 Repository Structure

```
Kubernetes-Observability-Stack/
├── README.md                              # This file
├── LICENSE                                # MIT License
├── .gitignore
│
├── helm-values/                           # Helm chart value overrides
│   ├── kube-prometheus-stack.yaml          # Prometheus + Alertmanager + Grafana
│   ├── loki.yaml                           # Loki log aggregation
│   └── promtail.yaml                       # Promtail log collection
│
├── sample-app/                            # Instrumented sample application
│   ├── main.go                             # Go HTTP server + Prometheus metrics
│   ├── go.mod                              # Go module dependencies
│   └── Dockerfile                          # Multi-stage distroless build
│
├── kubernetes/                            # Kubernetes manifests
│   ├── namespace.yaml                      # monitoring + sample-app namespaces
│   ├── sample-app/
│   │   ├── deployment.yaml                 # 2-replica deployment with annotations
│   │   ├── service.yaml                    # ClusterIP service
│   │   └── service-monitor.yaml            # ServiceMonitor CRD
│   ├── alerting/
│   │   └── prometheus-rules.yaml           # PrometheusRule CRD (5 alert rules)
│   └── webhook-receiver/
│       ├── deployment.yaml                 # Mock notification receiver
│       └── service.yaml                    # ClusterIP service
│
├── grafana-dashboards/                    # Dashboard JSON models
│   ├── kubernetes-cluster-overview.json    # Cluster health overview
│   └── application-performance.json        # App RED metrics + log correlation
│
└── scripts/                               # Automation scripts
    ├── deploy.sh                           # Full stack deployment
    ├── teardown.sh                         # Clean uninstall
    └── test-alerts.sh                      # Alert trigger tests
```

---

## 🔧 Configuration Reference

### Persistent Storage

| Component | PVC Size | Retention |
|-----------|----------|-----------|
| Prometheus | 50Gi | 15 days |
| Alertmanager | 5Gi | — |
| Grafana | 10Gi | — |
| Loki | 20Gi | 7 days |

### Key Configuration Files

- **Prometheus scraping**: `helm-values/kube-prometheus-stack.yaml` → `additionalScrapeConfigs`
- **Alert rules**: `kubernetes/alerting/prometheus-rules.yaml`
- **Alert routing**: `helm-values/kube-prometheus-stack.yaml` → `alertmanager.config`
- **Grafana data sources**: `helm-values/kube-prometheus-stack.yaml` → `grafana.additionalDataSources`
- **Loki storage**: `helm-values/loki.yaml` → `loki.storage`
- **Promtail scraping**: `helm-values/promtail.yaml` → `config.snippets.scrapeConfigs`

---

## 🧹 Teardown

```bash
# Remove all components (keeps PVCs)
./scripts/teardown.sh

# Remove all components AND persistent data
./scripts/teardown.sh --delete-pvcs
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Pods stuck in `Pending` | Check PVC binding: `kubectl get pvc -n monitoring` — ensure StorageClass exists |
| Prometheus not scraping app | Verify ServiceMonitor labels match: `kubectl get servicemonitor -n monitoring` |
| No logs in Loki | Check Promtail: `kubectl logs -l app.kubernetes.io/name=promtail -n monitoring` |
| Grafana dashboards empty | Verify data sources: Grafana → Configuration → Data Sources → Test |
| Alerts not firing | Check rule syntax: Prometheus UI → Status → Rules |
| Image pull errors | For Minikube: `eval $(minikube docker-env)` then rebuild image |

---

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
