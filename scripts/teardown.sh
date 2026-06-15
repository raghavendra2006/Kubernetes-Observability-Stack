#!/usr/bin/env bash
# ============================================================
# teardown.sh — Remove the Kubernetes Observability Stack
# ============================================================
# This script removes all components deployed by deploy.sh.
# It performs cleanup in reverse order to avoid dependency issues.
#
# Usage: ./scripts/teardown.sh [--delete-pvcs]
#
# Options:
#   --delete-pvcs    Also delete PersistentVolumeClaims (data loss!)
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DELETE_PVCS=false
if [[ "${1:-}" == "--delete-pvcs" ]]; then
    DELETE_PVCS=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║          ⚠️  TEARING DOWN OBSERVABILITY STACK  ⚠️            ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$DELETE_PVCS" == "true" ]]; then
    echo -e "${RED}WARNING: --delete-pvcs flag set. All persistent data will be deleted!${NC}"
fi

echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================
# Step 1: Remove Sample Application
# ============================================================

log_info "Removing sample application..."
kubectl delete -f "$PROJECT_DIR/kubernetes/sample-app/" --ignore-not-found=true 2>/dev/null || true
log_success "Sample application removed"

# ============================================================
# Step 2: Remove Alert Rules
# ============================================================

log_info "Removing alert rules..."
kubectl delete -f "$PROJECT_DIR/kubernetes/alerting/" --ignore-not-found=true 2>/dev/null || true
log_success "Alert rules removed"

# ============================================================
# Step 3: Remove Webhook Receiver
# ============================================================

log_info "Removing webhook receiver..."
kubectl delete -f "$PROJECT_DIR/kubernetes/webhook-receiver/" --ignore-not-found=true 2>/dev/null || true
log_success "Webhook receiver removed"

# ============================================================
# Step 4: Remove Dashboard ConfigMaps
# ============================================================

log_info "Removing Grafana dashboard ConfigMaps..."
kubectl delete configmap grafana-custom-dashboards -n monitoring --ignore-not-found=true 2>/dev/null || true
log_success "Dashboard ConfigMaps removed"

# ============================================================
# Step 5: Uninstall Promtail
# ============================================================

log_info "Uninstalling Promtail..."
helm uninstall promtail -n monitoring 2>/dev/null || true
log_success "Promtail uninstalled"

# ============================================================
# Step 6: Uninstall Loki
# ============================================================

log_info "Uninstalling Loki..."
helm uninstall loki -n monitoring 2>/dev/null || true
log_success "Loki uninstalled"

# ============================================================
# Step 7: Uninstall kube-prometheus-stack
# ============================================================

log_info "Uninstalling kube-prometheus-stack..."
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
log_success "kube-prometheus-stack uninstalled"

# ============================================================
# Step 8: Clean up CRDs (optional — they persist after helm uninstall)
# ============================================================

log_info "Cleaning up Prometheus Operator CRDs..."
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd alertmanagers.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd podmonitors.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd probes.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd prometheusagents.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd prometheuses.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd prometheusrules.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd scrapeconfigs.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd servicemonitors.monitoring.coreos.com 2>/dev/null || true
kubectl delete crd thanosrulers.monitoring.coreos.com 2>/dev/null || true
log_success "CRDs cleaned up"

# ============================================================
# Step 9: Delete PVCs (if requested)
# ============================================================

if [[ "$DELETE_PVCS" == "true" ]]; then
    log_info "Deleting PersistentVolumeClaims in monitoring namespace..."
    kubectl delete pvc --all -n monitoring 2>/dev/null || true
    log_success "PVCs deleted"
else
    log_warn "PVCs were NOT deleted. Use --delete-pvcs flag to also remove persistent data."
    echo "  To manually delete: kubectl delete pvc --all -n monitoring"
fi

# ============================================================
# Step 10: Delete Namespaces
# ============================================================

log_info "Deleting namespaces..."
kubectl delete namespace sample-app --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found=true 2>/dev/null || true
log_success "Namespaces deleted"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        🧹 OBSERVABILITY STACK TEARDOWN COMPLETE 🧹          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
