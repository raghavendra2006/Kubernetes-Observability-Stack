# Kubernetes Observability Stack: Video Demo Script

This document provides a highly structured, step-by-step script to record a professional, "over-excellence" video demonstration of the Kubernetes Observability Stack. It showcases the production-grade security, infrastructure-as-code robustness, and end-to-end event-driven alerting.

## Pre-Recording Setup
1. **Ensure Minikube is Running:** The stack should be running locally on Minikube.
2. **Open Three Terminal Tabs:**
   - **Tab 1:** Port-forward Grafana: `kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring`
   - **Tab 2:** Port-forward Prometheus: `kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring`
   - **Tab 3:** Port-forward Alertmanager: `kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring`
3. **Browser Tabs:**
   - Open Grafana: `http://localhost:3000` (Login: `admin` / `observability-admin`)
   - Open Prometheus: `http://localhost:9090/alerts`
   - Open Alertmanager: `http://localhost:9093/#/alerts`

---

## Video Script Sequence (10 Scenes)

### Scene 1: Introduction & Architecture (0:00 - 0:30)
* **Visual:** Display your IDE showing the project structure (`kube-prometheus-stack.yaml`, `deploy.sh`).
* **Talking Points:** 
  > "Hello, in this demonstration I will showcase our production-grade Kubernetes Observability Stack. This project integrates Prometheus for metrics, Loki for log aggregation, Grafana for visualization, and a custom Python webhook receiver for event-driven alert routing. My goal was not just to meet the baseline requirements, but to enforce strict, production-ready security constraints."

### Scene 2: Security & Infrastructure-as-Code Walkthrough (0:30 - 1:15)
* **Visual:** Open `kubernetes/sample-app/deployment.yaml` in your editor.
* **Talking Points:** 
  > "Let me highlight our security hardening. Notice in the sample app and webhook receiver manifests that we enforce `runAsNonRoot: true`, mandate a `readOnlyRootFilesystem`, and explicitly drop all Linux capabilities (`drop: - ALL`). Furthermore, no plain-text passwords exist in the Helm values; Grafana admin credentials are dynamically injected via Kubernetes Secrets during our automated deployment."

### Scene 3: Confirming Live Deployment (1:15 - 1:45)
* **Visual:** Switch to your terminal.
* **Action:** Run `kubectl get pods -A`
* **Talking Points:** 
  > "As you can see, the entire stack is currently running locally on Minikube. The automated deployment script ensures repeatable, identical infrastructure provisioning across any Kubernetes environment."

### Scene 4: Dashboard Walkthrough & Log Correlation (1:45 - 2:30)
* **Visual:** Switch to Grafana in your browser (`http://localhost:3000/d/app-performance`).
* **Action:** Briefly show the dashboard.
* **Talking Points:** 
  > "Here is our Application Performance dashboard. A key architectural achievement here is the seamless correlation between metrics and logs. The Loki datasource uses dynamic derived fields, meaning that if we detect a metric anomaly in a specific pod, we can instantly pivot directly into the corresponding Loki logs for that exact container without losing context."

### Scene 5: Initiating the End-to-End Alert Test (2:30 - 3:00)
* **Visual:** Open your terminal.
* **Action:** Run the load generation test: `bash scripts/test-alerts.sh all`
* **Talking Points:** 
  > "To demonstrate the event-driven observability flow, I'm executing an automated test script. This script dynamically provisions a Pod designed to fail into a `CrashLoopBackOff` state, and injects HTTP 500 error traffic into our sample application to simulate a live outage."

### Scene 6: Observing Metrics Spike in Grafana (3:00 - 3:30)
* **Visual:** Switch back to the Grafana "Application Performance" dashboard.
* **Action:** Point to the error rate graph spiking.
* **Talking Points:** 
  > "Immediately, we can see the spike in 5xx HTTP errors being scraped by Prometheus and visualized here in Grafana. The PromQL expressions behind these panels dynamically track the ratio of failed requests against total traffic."

### Scene 7: Alert Triggering in Prometheus (3:30 - 4:00)
* **Visual:** Switch to the Prometheus Alerts UI (`http://localhost:9090/alerts`).
* **Action:** Filter by `PodCrashLooping` or `HighApplicationErrorRate`.
* **Talking Points:** 
  > "Moving to Prometheus, our custom alerting rules have evaluated those metrics. You can see the alerts transitioning from `Pending` to `Firing`. For example, the `HighApplicationErrorRate` alert is explicitly configured to fire when the error threshold exceeds 5%."

### Scene 8: Alert Routing via Alertmanager (4:00 - 4:30)
* **Visual:** Switch to the Alertmanager UI (`http://localhost:9093/#/alerts`).
* **Talking Points:** 
  > "Prometheus forwards these firing alerts to Alertmanager. Here, alerts are deduplicated, grouped by severity, and intelligently routed to their destination—in this case, our custom webhook receiver."

### Scene 9: Webhook Event Reception (4:30 - 5:00)
* **Visual:** Terminal window.
* **Action:** Run `kubectl logs -l app=alertmanager-webhook-receiver -n monitoring --tail=30`
* **Talking Points:** 
  > "Finally, let's verify the delivery. By inspecting the logs of our custom Python webhook receiver, we can see the incoming JSON payloads containing the critical alert details. In a production environment, this event-driven receiver could automatically trigger remediation scripts, create Jira tickets, or page the on-call engineer."

### Scene 10: Conclusion (5:00 - 5:15)
* **Visual:** Back to the IDE.
* **Talking Points:** 
  > "This concludes the demonstration. The stack enforces strict security, provides deep observability through metric-log correlation, and successfully executes a complete event-driven alerting lifecycle. Thank you."
