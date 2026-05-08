#!/bin/bash

# =============================================================================
# Pentaho AWS EKS Monitoring and Management Setup Script
# =============================================================================
# This script sets up comprehensive monitoring and management for Pentaho:
# - CloudWatch integration for logs and metrics
# - Prometheus and Grafana for application monitoring
# - Backup and restore automation
# - Health checks and alerting

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons for better UX
CHECK="✅"
ERROR="❌"
ARROW="➤"
INFO="ℹ️"
GEAR="⚙️"
MONITOR="📊"
BACKUP="💾"
ALERT="🚨"

# Function to print colored output
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_info() { log "$BLUE" "$INFO $1"; }
log_success() { log "$GREEN" "$CHECK $1"; }
log_warning() { log "$YELLOW" "⚠️ $1"; }
log_error() { log "$RED" "$ERROR $1"; }
log_step() { log "$YELLOW" "$ARROW $1"; }
log_monitor() { log "$CYAN" "$MONITOR $1"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    local missing_commands=()
    
    # Check required commands
    if ! command_exists kubectl; then missing_commands+=("kubectl"); fi
    if ! command_exists helm; then missing_commands+=("helm"); fi
    if ! command_exists jq; then missing_commands+=("jq"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install missing tools:"
        log_info "  brew install kubectl helm jq"
        exit 1
    fi
    
    # Check AWS authentication via okta-aws
    log_info "Validating AWS credentials via okta-aws..."
    if [ -n "${AWS_PROFILE:-}" ]; then
        if ! okta-aws "${AWS_PROFILE}" sts get-caller-identity >/dev/null 2>&1; then
            log_error "AWS authentication failed."
            log_info "Please run: okta-aws $AWS_PROFILE sts get-caller-identity"
            exit 1
        fi
    else
        log_error "AWS_PROFILE not set. Please configure your AWS profile."
        log_info "Please run: okta-aws yourprofile sts get-caller-identity"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to load environment configuration
load_environment() {
    local env_name="${1:-}"
    
    if [ -z "$env_name" ]; then
        log_error "Environment name not provided"
        echo "Usage: $0 <environment>"
        echo "Example: $0 dev"
        exit 1
    fi
    
    local env_file="pentaho-eks-${env_name}.env"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi
    
    if [ ! -f "$runtime_file" ]; then
        log_error "Runtime state file not found: $runtime_file"
        log_info "Please run the deployment scripts first"
        exit 1
    fi
    
    log_step "Loading configuration..."
    source "$env_file"
    source "$runtime_file"
    
    # Set up AWS environment using okta-aws
    if [ -n "${AWS_PROFILE:-}" ]; then
        log_info "Setting up AWS credentials via okta-aws profile: $AWS_PROFILE"
        eval "$(okta-aws "$AWS_PROFILE" env)"
        export AWS_PROFILE="$AWS_PROFILE"
    fi
    
    # Validate deployment is ready
    if [ "${PENTAHO_DEPLOYED:-false}" != "true" ]; then
        log_error "Pentaho deployment not completed. Please run: ./04-deploy-pentaho.sh $env_name"
        exit 1
    fi
    
    log_success "Configuration loaded for environment: $env_name"
}

# Function to setup CloudWatch logging
setup_cloudwatch_logging() {
    log_step "Setting up CloudWatch logging..."
    
    # Create CloudWatch log group
    local log_group="/aws/eks/${EKS_CLUSTER_NAME}/pentaho"
    
    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "$AWS_REGION" 2>/dev/null || {
        log_info "CloudWatch log group already exists"
    }
    
    # Set log retention
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days 30 \
        --region "$AWS_REGION"
    
    # Create Fluent Bit configuration
    local fluentbit_config="monitoring/fluent-bit-config.yaml"
    mkdir -p "$(dirname "$fluentbit_config")"
    
    cat > "$fluentbit_config" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: ${K8S_NAMESPACE}
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020

    [INPUT]
        Name              tail
        Path              /var/log/containers/pentaho-server*.log
        Parser            docker
        Tag               kube.pentaho.logs
        Refresh_Interval  5
        Mem_Buf_Limit     50MB

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log           On
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off

    [OUTPUT]
        Name                cloudwatch_logs
        Match               kube.pentaho.*
        region              ${AWS_REGION}
        log_group_name      ${log_group}
        log_stream_prefix   pentaho-
        auto_create_group   false

  parsers.conf: |
    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
        Time_Keep   On
EOF

    kubectl apply -f "$fluentbit_config"
    log_success "CloudWatch logging configured"
}

# Function to install Prometheus and Grafana
setup_prometheus_grafana() {
    log_step "Setting up Prometheus and Grafana monitoring..."
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Prometheus
    log_monitor "Installing Prometheus..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.prometheusSpec.retention=7d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi \
        --set grafana.enabled=true \
        --set grafana.persistence.enabled=true \
        --set grafana.persistence.size=10Gi \
        --set alertmanager.enabled=true \
        --wait
    
    # Create ServiceMonitor for Pentaho
    local servicemonitor_file="monitoring/pentaho-servicemonitor.yaml"
    
    cat > "$servicemonitor_file" << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pentaho-monitor
  namespace: monitoring
  labels:
    app: pentaho-server
spec:
  selector:
    matchLabels:
      app: pentaho-server
  namespaceSelector:
    matchNames:
    - ${K8S_NAMESPACE}
  endpoints:
  - port: http
    path: /pentaho/api/system/metrics
    interval: 30s
---
apiVersion: v1
kind: Service
metadata:
  name: pentaho-metrics
  namespace: ${K8S_NAMESPACE}
  labels:
    app: pentaho-server
    metrics: enabled
spec:
  type: ClusterIP
  selector:
    app: pentaho-server
  ports:
  - name: metrics
    port: 9090
    targetPort: 8080
    protocol: TCP
EOF

    kubectl apply -f "$servicemonitor_file"
    log_success "Prometheus and Grafana installed"
}

# Function to create Grafana dashboard for Pentaho
create_grafana_dashboard() {
    log_step "Creating Pentaho Grafana dashboard..."
    
    local dashboard_file="monitoring/pentaho-dashboard.json"
    
    cat > "$dashboard_file" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Pentaho Server Monitoring",
    "tags": ["pentaho", "kubernetes"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Pentaho Server Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"pentaho-server\"}",
            "legendFormat": "Server Status"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "HTTP Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"pentaho-server\"}[5m])",
            "legendFormat": "Requests/sec"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{pod=~\"pentaho-server.*\"}",
            "legendFormat": "Memory Usage"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{pod=~\"pentaho-server.*\"}[5m])",
            "legendFormat": "CPU Usage"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "30s"
  }
}
EOF

    # Get Grafana admin password
    local grafana_password
    grafana_password=$(kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    
    log_success "Grafana dashboard template created"
    log_info "Grafana admin password: $grafana_password"
}

# Function to setup backup automation
setup_backup_automation() {
    log_step "Setting up backup automation..."
    
    # Create backup script
    local backup_script="scripts/backup-pentaho.sh"
    mkdir -p "$(dirname "$backup_script")"
    
    cat > "$backup_script" << EOF
#!/bin/bash

# Pentaho Backup Script for Kubernetes
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE}"
BACKUP_BUCKET="${S3_BUCKET_NAME}"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/pentaho-backup-\$TIMESTAMP"

echo "Starting Pentaho backup..."

# Create backup directory
mkdir -p "\$BACKUP_DIR"

# Backup persistent volumes
echo "Backing up persistent volumes..."
kubectl exec -n "\$NAMESPACE" deployment/pentaho-server -- tar czf - -C /opt/pentaho/pentaho-server/pentaho-solutions/system/data . > "\$BACKUP_DIR/pentaho-data.tar.gz"

# Backup database
echo "Backing up databases..."
kubectl exec -n "\$NAMESPACE" deployment/pentaho-server -- pg_dump -h \$JCR_DB_HOST -U \$JCR_DB_USER -d \$JCR_DB_NAME > "\$BACKUP_DIR/jcr-backup.sql"
kubectl exec -n "\$NAMESPACE" deployment/pentaho-server -- pg_dump -h \$QUARTZ_DB_HOST -U \$QUARTZ_DB_USER -d \$QUARTZ_DB_NAME > "\$BACKUP_DIR/quartz-backup.sql"

# Backup configurations
echo "Backing up configurations..."
kubectl get configmap -n "\$NAMESPACE" -o yaml > "\$BACKUP_DIR/configmaps.yaml"
kubectl get secret -n "\$NAMESPACE" -o yaml > "\$BACKUP_DIR/secrets.yaml"

# Upload to S3
echo "Uploading backup to S3..."
tar czf - -C "\$BACKUP_DIR" . | aws s3 cp - "s3://\$BACKUP_BUCKET/pentaho-backups/backup-\$TIMESTAMP.tar.gz"

# Cleanup
rm -rf "\$BACKUP_DIR"

echo "Backup completed: s3://\$BACKUP_BUCKET/pentaho-backups/backup-\$TIMESTAMP.tar.gz"
EOF

    chmod +x "$backup_script"
    
    # Create CronJob for automated backups
    local cronjob_file="monitoring/backup-cronjob.yaml"
    
    cat > "$cronjob_file" << EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pentaho-backup
  namespace: ${K8S_NAMESPACE}
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: ${PENTAHO_ECR_IMAGE_URI}
            command:
            - /bin/bash
            - -c
            - |
              # Backup script content embedded here
              $(cat "$backup_script" | sed 's/^/              /')
            env:
            - name: JCR_DB_HOST
              valueFrom:
                secretKeyRef:
                  name: pentaho-jcr-db
                  key: host
            - name: JCR_DB_USER
              valueFrom:
                secretKeyRef:
                  name: pentaho-jcr-db
                  key: username
            # Add other environment variables as needed
          restartPolicy: OnFailure
EOF

    kubectl apply -f "$cronjob_file"
    log_success "Backup automation configured"
}

# Function to setup health checks and alerting
setup_health_checks() {
    log_step "Setting up health checks and alerting..."
    
    # Create health check script
    local health_script="scripts/health-check.sh"
    
    cat > "$health_script" << EOF
#!/bin/bash

# Pentaho Health Check Script
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE}"
HEALTH_ENDPOINT="http://pentaho-server-internal.\${NAMESPACE}.svc.cluster.local:8080/pentaho/api/system/health"

echo "Performing Pentaho health check..."

# Check pod status
RUNNING_PODS=\$(kubectl get pods -n "\$NAMESPACE" -l app=pentaho-server --field-selector=status.phase=Running --no-headers | wc -l)
if [ "\$RUNNING_PODS" -eq 0 ]; then
    echo "ERROR: No Pentaho pods are running"
    exit 1
fi

# Check service endpoint
if ! kubectl exec -n "\$NAMESPACE" deployment/pentaho-server -- curl -sf "\$HEALTH_ENDPOINT" >/dev/null; then
    echo "ERROR: Pentaho health endpoint is not responding"
    exit 1
fi

echo "Health check passed"
EOF

    chmod +x "$health_script"
    
    # Create Prometheus alerts
    local alerts_file="monitoring/pentaho-alerts.yaml"
    
    cat > "$alerts_file" << EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pentaho-alerts
  namespace: monitoring
  labels:
    app: pentaho-server
spec:
  groups:
  - name: pentaho.rules
    rules:
    - alert: PentahoDown
      expr: up{job="pentaho-server"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Pentaho server is down"
        description: "Pentaho server has been down for more than 1 minute"
    
    - alert: PentahoHighMemoryUsage
      expr: container_memory_usage_bytes{pod=~"pentaho-server.*"} / container_spec_memory_limit_bytes > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pentaho server high memory usage"
        description: "Pentaho server memory usage is above 90%"
    
    - alert: PentahoHighCPUUsage
      expr: rate(container_cpu_usage_seconds_total{pod=~"pentaho-server.*"}[5m]) > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pentaho server high CPU usage"
        description: "Pentaho server CPU usage is above 80%"
EOF

    kubectl apply -f "$alerts_file"
    log_success "Health checks and alerting configured"
}

# Function to create management scripts
create_management_scripts() {
    log_step "Creating management scripts..."
    
    mkdir -p scripts
    
    # Create scale script
    cat > "scripts/scale-pentaho.sh" << EOF
#!/bin/bash
# Scale Pentaho deployment
REPLICAS=\${1:-1}
kubectl scale deployment pentaho-server --replicas=\$REPLICAS -n ${K8S_NAMESPACE}
echo "Scaling Pentaho to \$REPLICAS replicas"
EOF
    
    # Create restart script
    cat > "scripts/restart-pentaho.sh" << EOF
#!/bin/bash
# Restart Pentaho deployment
kubectl rollout restart deployment/pentaho-server -n ${K8S_NAMESPACE}
kubectl rollout status deployment/pentaho-server -n ${K8S_NAMESPACE}
echo "Pentaho restarted successfully"
EOF
    
    # Create logs script
    cat > "scripts/get-logs.sh" << EOF
#!/bin/bash
# Get Pentaho logs
LINES=\${1:-100}
kubectl logs -n ${K8S_NAMESPACE} -l app=pentaho-server --tail=\$LINES
EOF
    
    # Create shell access script
    cat > "scripts/shell-access.sh" << EOF
#!/bin/bash
# Get shell access to Pentaho pod
POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=pentaho-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it \$POD -n ${K8S_NAMESPACE} -- /bin/bash
EOF
    
    chmod +x scripts/*.sh
    log_success "Management scripts created"
}

# Function to update runtime state
update_runtime_state() {
    local env_name="$1"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    log_step "Updating runtime state..."
    
    cat >> "$runtime_file" << EOF

# Monitoring Information - Updated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
MONITORING_ENABLED=true
PROMETHEUS_INSTALLED=true
GRAFANA_INSTALLED=true
CLOUDWATCH_LOGGING=true
BACKUP_AUTOMATION=true
HEALTH_CHECKS=true
MONITORING_SETUP_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log_success "Runtime state updated"
}

# Function to display summary
display_summary() {
    local env_name="$1"
    
    log_success "Monitoring and management setup completed!"
    echo
    log_info "Setup Summary:"
    echo "  Environment: $env_name"
    echo "  CloudWatch Logging: Enabled"
    echo "  Prometheus: Installed"
    echo "  Grafana: Installed"
    echo "  Backup Automation: Enabled"
    echo "  Health Checks: Enabled"
    echo
    
    # Get Grafana URL
    local grafana_service
    grafana_service=$(kubectl get service --namespace monitoring prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    if [ "$grafana_service" != "pending" ]; then
        log_info "Access URLs:"
        echo "  Grafana: http://$grafana_service"
    else
        log_info "Port forward to access Grafana:"
        echo "  kubectl port-forward --namespace monitoring service/prometheus-grafana 3000:80"
        echo "  Then access: http://localhost:3000"
    fi
    
    echo
    log_info "Management Scripts:"
    echo "  ./scripts/scale-pentaho.sh <replicas>   - Scale deployment"
    echo "  ./scripts/restart-pentaho.sh            - Restart deployment"
    echo "  ./scripts/get-logs.sh <lines>           - Get application logs"
    echo "  ./scripts/shell-access.sh               - Access pod shell"
    echo "  ./scripts/backup-pentaho.sh             - Manual backup"
    echo "  ./scripts/health-check.sh               - Run health check"
    echo
    
    log_info "Monitoring Commands:"
    echo "  # View Grafana dashboards"
    echo "  kubectl port-forward --namespace monitoring service/prometheus-grafana 3000:80"
    echo
    echo "  # Check Prometheus targets"
    echo "  kubectl port-forward --namespace monitoring service/prometheus-kube-prometheus-prometheus 9090:9090"
    echo
    echo "  # View CloudWatch logs"
    echo "  aws logs tail /aws/eks/${EKS_CLUSTER_NAME}/pentaho --follow"
}

# Main execution
main() {
    local env_name="${1:-}"
    
    echo "📊 Pentaho AWS EKS Monitoring Setup"
    echo "==================================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    
    log_info "Setting up monitoring for environment: $env_name"
    log_info "Cluster: $EKS_CLUSTER_NAME"
    log_info "Namespace: $K8S_NAMESPACE"
    echo
    
    setup_cloudwatch_logging
    setup_prometheus_grafana
    create_grafana_dashboard
    setup_backup_automation
    setup_health_checks
    create_management_scripts
    
    update_runtime_state "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
