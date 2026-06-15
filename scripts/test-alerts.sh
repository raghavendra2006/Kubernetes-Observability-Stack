#!/usr/bin/env bash
# ============================================================
# test-alerts.sh — Trigger test alerts for the Observability Stack
# ============================================================
# This script creates conditions to trigger each of the defined
# Prometheus alert rules, so you can verify that:
#   1. Alerts fire correctly in Prometheus
#   2. Alerts appear in Alertmanager
#   3. Notifications are sent to the webhook receiver
#
# Usage: ./scripts/test-alerts.sh [alert-name]
#
# Examples:
#   ./scripts/test-alerts.sh             # Run all tests
#   ./scripts/test-alerts.sh crashloop   # Test only CrashLoopBackOff
#   ./scripts/test-alerts.sh errors      # Test only high error rate
#   ./scripts/test-alerts.sh cpu         # Test only high CPU
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_test() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  TEST: $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

TARGET="${1:-all}"

# ============================================================
# Test 1: High Application Error Rate
# ============================================================
test_high_error_rate() {
    log_test "High Application Error Rate (HighApplicationErrorRate)"
    log_info "Sending rapid requests to the /error endpoint to trigger >5% error rate..."

    # Get sample app pod for port-forwarding
    local pod
    pod=$(kubectl get pods -n sample-app -l app=sample-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        log_error "No sample-app pods found. Is the sample app deployed?"
        return 1
    fi

    # Port-forward in background
    kubectl port-forward "pod/$pod" 8888:8080 -n sample-app &>/dev/null &
    local pf_pid=$!
    sleep 2

    log_info "Generating error traffic (200 error requests)..."
    for i in $(seq 1 200); do
        curl -s -o /dev/null http://localhost:8888/error &
        if (( i % 50 == 0 )); then
            echo -e "  Sent $i/200 error requests..."
        fi
    done
    wait

    # Also send some normal traffic to maintain a ratio
    log_info "Generating some normal traffic (50 requests)..."
    for i in $(seq 1 50); do
        curl -s -o /dev/null http://localhost:8888/ &
    done
    wait

    # Clean up port-forward
    kill $pf_pid 2>/dev/null || true

    log_success "Error traffic generated!"
    log_info "The HighApplicationErrorRate alert should fire within ~2-5 minutes."
    log_info "Check Prometheus: http://localhost:9090/alerts"
    log_info "Check Alertmanager: http://localhost:9093/#/alerts"
}

# ============================================================
# Test 2: Pod CrashLoopBackOff
# ============================================================
test_crashloop() {
    log_test "Pod CrashLoopBackOff (PodCrashLooping)"
    log_info "Deploying a pod that will immediately crash and enter CrashLoopBackOff..."

    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: crashloop-test
  namespace: sample-app
  labels:
    app: crashloop-test
    test: alert-trigger
spec:
  containers:
    - name: crasher
      image: busybox:latest
      command: ["sh", "-c", "echo 'This pod is designed to crash for alert testing' && exit 1"]
      resources:
        requests:
          cpu: "10m"
          memory: "16Mi"
        limits:
          cpu: "50m"
          memory: "32Mi"
  restartPolicy: Always
EOF

    log_success "Crash-loop test pod deployed!"
    log_info "The PodCrashLooping alert should fire within ~5-10 minutes."
    log_info "Watch the pod: kubectl get pod crashloop-test -n sample-app -w"
    log_info ""
    log_warn "To clean up: kubectl delete pod crashloop-test -n sample-app"
}

# ============================================================
# Test 3: High CPU Usage
# ============================================================
test_high_cpu() {
    log_test "High CPU Usage (HighCPUUsage)"
    log_info "Deploying a stress test pod to consume CPU..."

    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cpu-stress-test
  namespace: sample-app
  labels:
    app: cpu-stress-test
    test: alert-trigger
spec:
  containers:
    - name: stress
      image: busybox:latest
      command: ["sh", "-c", "while true; do :; done"]
      resources:
        requests:
          cpu: "100m"
          memory: "32Mi"
        limits:
          cpu: "100m"
          memory: "64Mi"
  restartPolicy: Always
EOF

    log_success "CPU stress test pod deployed!"
    log_info "The HighCPUUsage alert should fire within ~5-10 minutes."
    log_info "The pod has a 100m CPU limit and will consume 100% of it."
    log_info ""
    log_warn "To clean up: kubectl delete pod cpu-stress-test -n sample-app"
}

# ============================================================
# Cleanup Function
# ============================================================
cleanup_test_resources() {
    log_test "Cleaning Up Test Resources"
    log_info "Removing test pods..."

    kubectl delete pod crashloop-test -n sample-app --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod cpu-stress-test -n sample-app --ignore-not-found=true 2>/dev/null || true

    log_success "Test resources cleaned up"
}

# ============================================================
# Verification Instructions
# ============================================================
print_verification() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              📋 ALERT VERIFICATION GUIDE                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}1. Check Prometheus Alerts:${NC}"
    echo "     kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
    echo "     Open: http://localhost:9090/alerts"
    echo "     → Look for alerts in 'firing' or 'pending' state"
    echo ""
    echo -e "  ${YELLOW}2. Check Alertmanager:${NC}"
    echo "     kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring"
    echo "     Open: http://localhost:9093/#/alerts"
    echo "     → Verify alerts are received and grouped"
    echo ""
    echo -e "  ${YELLOW}3. Check Webhook Receiver Logs:${NC}"
    echo "     kubectl logs -l app=alertmanager-webhook-receiver -n monitoring --tail=50"
    echo "     → Verify alert payloads are logged"
    echo ""
    echo -e "  ${YELLOW}4. Check Grafana Dashboards:${NC}"
    echo "     kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
    echo "     Open: http://localhost:3000/d/app-performance"
    echo "     → Observe error rate spike and correlate with logs"
    echo ""
    echo -e "  ${YELLOW}5. Clean up test resources:${NC}"
    echo "     ./scripts/test-alerts.sh cleanup"
    echo ""
}

# ============================================================
# Main
# ============================================================

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          🧪 ALERT TESTING — OBSERVABILITY STACK 🧪          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

case "$TARGET" in
    errors|error)
        test_high_error_rate
        ;;
    crashloop|crash)
        test_crashloop
        ;;
    cpu)
        test_high_cpu
        ;;
    cleanup|clean)
        cleanup_test_resources
        ;;
    all)
        test_high_error_rate
        echo ""
        sleep 2
        test_crashloop
        echo ""
        sleep 2
        test_high_cpu
        ;;
    *)
        echo "Usage: $0 [errors|crashloop|cpu|cleanup|all]"
        exit 1
        ;;
esac

print_verification
