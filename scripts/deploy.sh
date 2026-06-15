#!/usr/bin/env bash
# ============================================================
# deploy.sh — Deploy the Kubernetes Observability Stack
# ============================================================
# This script deploys the complete observability stack:
#   1. Namespaces
#   2. kube-prometheus-stack (Prometheus Operator + Prometheus + Alertmanager + Grafana)
#   3. Loki (Log aggregation)
#   4. Promtail (Log collection DaemonSet)
#   5. Auto-building and loading of sample application image
#   6. Sample application deployment
#   7. Webhook receiver (Alertmanager target)
#   8. PrometheusRule alert definitions
#   9. Grafana dashboard ConfigMaps
#
# Usage: ./scripts/deploy.sh
# ============================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ============================================================
# Helper Functions
# ============================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  STEP: $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    log_info "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."
    if kubectl wait --for=condition=ready pod --all -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_success "All pods in '$namespace' are ready"
    else
        log_warn "Some pods in '$namespace' may not be ready yet. Check: kubectl get pods -n $namespace"
    fi
}

# ============================================================
# Pre-flight Checks
# ============================================================

log_step "Pre-flight Checks"

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi
log_success "kubectl found"

# Check helm
if ! command -v helm &>/dev/null; then
    log_error "Helm is not installed. Please install Helm first: https://helm.sh/docs/intro/install/"
    exit 1
fi
log_success "Helm found: $(helm version --short)"

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi
log_success "Connected to Kubernetes cluster"

# ============================================================
# Step 1: Create Namespaces
# ============================================================

log_step "1/9 — Creating Namespaces and Secrets"

kubectl apply -f "$PROJECT_DIR/kubernetes/namespace.yaml"
log_success "Namespaces 'monitoring' and 'sample-app' created"

# Create Grafana admin credentials secret if it doesn't exist
if ! kubectl get secret grafana-admin-credentials -n monitoring &>/dev/null; then
    log_info "Creating Grafana admin credentials secret..."
    kubectl create secret generic grafana-admin-credentials -n monitoring \
        --from-literal=admin-user="admin" \
        --from-literal=admin-password="observability-admin"
    log_success "Grafana admin credentials secret created"
else
    log_info "Grafana admin credentials secret already exists"
fi

# ============================================================
# Step 2: Add Helm Repositories
# ============================================================

log_step "2/9 — Adding Helm Repositories"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
log_success "Helm repositories added and updated"

# ============================================================
# Step 3: Deploy kube-prometheus-stack
# ============================================================

log_step "3/9 — Deploying kube-prometheus-stack (Prometheus + Alertmanager + Grafana)"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "$PROJECT_DIR/helm-values/kube-prometheus-stack.yaml" \
    --wait \
    --timeout 10m

log_success "kube-prometheus-stack deployed"

# ============================================================
# Step 4: Deploy Loki
# ============================================================

log_step "4/9 — Deploying Loki (Log Aggregation)"

helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values "$PROJECT_DIR/helm-values/loki.yaml" \
    --wait \
    --timeout 10m

log_success "Loki deployed"

# ============================================================
# Step 5: Deploy Promtail
# ============================================================

log_step "5/9 — Deploying Promtail (Log Collection DaemonSet)"

helm upgrade --install promtail grafana/promtail \
    --namespace monitoring \
    --values "$PROJECT_DIR/helm-values/promtail.yaml" \
    --wait \
    --timeout 5m

log_success "Promtail deployed"

# ============================================================
# Step 6: Deploy Webhook Receiver
# ============================================================

log_step "6/9 — Deploying Alertmanager Webhook Receiver"

kubectl apply -f "$PROJECT_DIR/kubernetes/webhook-receiver/"
log_success "Webhook receiver deployed"

# ============================================================
# Step 7: Build & Load Sample Application Image
# ============================================================

log_step "7/9 — Auto-Building and Loading Sample App Image"

IMAGE_NAME="sample-observability-app:latest"

if command -v minikube &>/dev/null && minikube status &>/dev/null; then
    log_info "Minikube detected. Building and loading the image inside Minikube context..."
    # Build directly inside minikube container runtime
    if minikube image build -t "$IMAGE_NAME" "$PROJECT_DIR/sample-app"; then
        log_success "Image '$IMAGE_NAME' built inside Minikube context successfully"
    else
        log_warn "Minikube image build failed. Falling back to local docker build..."
        docker build -t "$IMAGE_NAME" "$PROJECT_DIR/sample-app"
        minikube image load "$IMAGE_NAME"
        log_success "Image loaded into Minikube successfully"
    fi
elif command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q .; then
    CLUSTER_NAME=$(kind get clusters 2>/dev/null | head -n 1)
    log_info "Kind cluster '$CLUSTER_NAME' detected. Building image locally and loading into cluster..."
    docker build -t "$IMAGE_NAME" "$PROJECT_DIR/sample-app"
    kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"
    log_success "Image '$IMAGE_NAME' loaded into Kind cluster '$CLUSTER_NAME'"
elif command -v docker &>/dev/null && docker info &>/dev/null; then
    log_info "Standard Docker cluster environment detected. Building image locally..."
    docker build -t "$IMAGE_NAME" "$PROJECT_DIR/sample-app"
    log_success "Image '$IMAGE_NAME' built successfully"
else
    log_warn "Neither Minikube, Kind, nor running Docker daemon was detected. Deployment will use existing image (if cached)."
fi

# ============================================================
# Step 8: Deploy Sample Application
# ============================================================

log_step "8/9 — Deploying Sample Application"

kubectl apply -f "$PROJECT_DIR/kubernetes/sample-app/"
log_success "Sample application deployed"

# ============================================================
# Step 9: Apply Alert Rules and Dashboard ConfigMaps
# ============================================================

log_step "9/9 — Applying Alert Rules and Grafana Dashboards"

# Apply PrometheusRule alert definitions
kubectl apply -f "$PROJECT_DIR/kubernetes/alerting/"
log_success "Prometheus alert rules applied"

# Create Grafana dashboard ConfigMap
kubectl create configmap grafana-custom-dashboards \
    --from-file="$PROJECT_DIR/grafana-dashboards/kubernetes-cluster-overview.json" \
    --from-file="$PROJECT_DIR/grafana-dashboards/application-performance.json" \
    --namespace monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

# Label the ConfigMap for Grafana sidecar discovery
kubectl label configmap grafana-custom-dashboards \
    grafana_dashboard=1 \
    --namespace monitoring \
    --overwrite

log_success "Grafana dashboard ConfigMaps applied"

# ============================================================
# Wait for All Pods
# ============================================================

log_step "Waiting for All Pods to be Ready"

wait_for_pods "monitoring" 600
wait_for_pods "sample-app" 120

# ============================================================
# Summary & Access Instructions
# ============================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          🎉 OBSERVABILITY STACK DEPLOYED SUCCESSFULLY! 🎉    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}📊 Pod Status:${NC}"
echo "  monitoring namespace:"
kubectl get pods -n monitoring --no-headers | sed 's/^/    /'
echo ""
echo "  sample-app namespace:"
kubectl get pods -n sample-app --no-headers | sed 's/^/    /'
echo ""

echo -e "${CYAN}🔗 Access the UIs (run these port-forward commands):${NC}"
echo ""
echo -e "  ${YELLOW}Grafana:${NC}"
echo "    kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
echo "    URL:      http://localhost:3000"
echo "    Username: admin"
echo "    Password: observability-admin"
echo ""
echo -e "  ${YELLOW}Prometheus:${NC}"
echo "    kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
echo "    URL:      http://localhost:9090"
echo ""
echo -e "  ${YELLOW}Alertmanager:${NC}"
echo "    kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring"
echo "    URL:      http://localhost:9093"
echo ""
echo -e "  ${YELLOW}Sample App:${NC}"
echo "    kubectl port-forward svc/sample-app 8080:8080 -n sample-app"
echo "    URL:      http://localhost:8080"
echo "    Metrics:  http://localhost:8080/metrics"
echo ""

echo -e "${CYAN}📈 Grafana Dashboards:${NC}"
echo "  • Kubernetes Cluster Overview: http://localhost:3000/d/k8s-cluster-overview"
echo "  • Application Performance:     http://localhost:3000/d/app-performance"
echo ""

echo -e "${CYAN}🧪 Test alerts:${NC}"
echo "  ./scripts/test-alerts.sh"
echo ""
