#!/bin/bash

# =============================================================================
# Pentaho AWS EKS Deployment Script
# =============================================================================
# This script handles the complete Pentaho deployment to Kubernetes:
# - Configures kubectl for EKS cluster
# - Generates Kubernetes manifests from templates
# - Deploys Pentaho server with proper configuration
# - Sets up services, ingress, and monitoring

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
KUBE="☸️"
ROCKET="🚀"
MONITOR="📊"

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
log_kube() { log "$CYAN" "$KUBE $1"; }

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
    if ! command_exists jq; then missing_commands+=("jq"); fi
    if ! command_exists envsubst; then missing_commands+=("gettext (envsubst)"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install missing tools:"
        log_info "  brew install kubectl jq gettext"
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
        log_info "Please run the setup scripts first:"
        log_info "  1. ./01-setup-infrastructure.sh $env_name"
        log_info "  2. ./02-prepare-images.sh $env_name"
        log_info "  3. ./03-setup-database.sh $env_name"
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
    
    # Validate required runtime state
    if [ -z "${RDS_ENDPOINT_RESOLVED:-}" ] || [ "${JCR_DB_READY:-false}" != "true" ] || [ "${QUARTZ_DB_READY:-false}" != "true" ]; then
        log_error "Database setup incomplete. Please run: ./03-setup-database.sh $env_name"
        exit 1
    fi
    
    if [ -z "${PENTAHO_ECR_IMAGE_URI:-}" ]; then
        log_error "Image preparation incomplete. Please run: ./02-prepare-images.sh $env_name"
        exit 1
    fi
    
    log_success "Configuration loaded for environment: $env_name"
}

# Function to configure kubectl for EKS
configure_kubectl() {
    log_step "Configuring kubectl for EKS cluster..."
    
    # Update kubeconfig for EKS cluster
    if aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"; then
        log_success "kubectl configured for cluster: $EKS_CLUSTER_NAME"
    else
        log_error "Failed to configure kubectl"
        return 1
    fi
    
    # Test cluster connectivity
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Cluster connectivity verified"
    else
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Display cluster information
    local cluster_version
    cluster_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || echo "unknown")
    log_info "Cluster version: $cluster_version"
}

# Function to create namespace and basic resources
setup_namespace() {
    log_step "Setting up Kubernetes namespace..."
    
    # Create namespace
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply existing basic resources
    if [ -f "kubernetes/namespace.yaml" ]; then
        log_kube "Applying namespace configuration..."
        envsubst < kubernetes/namespace.yaml | kubectl apply -f -
    fi
    
    if [ -f "kubernetes/persistent-volume.yaml" ]; then
        log_kube "Applying persistent volume configuration..."
        envsubst < kubernetes/persistent-volume.yaml | kubectl apply -f -
    fi
    
    log_success "Namespace and basic resources configured"
}

# Function to generate Pentaho deployment manifest
generate_pentaho_deployment() {
    log_step "Generating Pentaho deployment manifest..."
    
    local deployment_file="kubernetes/pentaho-deployment.yaml"
    
    cat > "$deployment_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pentaho-server
  namespace: ${K8S_NAMESPACE}
  labels:
    app: pentaho-server
    tier: application
    environment: ${ENVIRONMENT}
spec:
  replicas: ${PENTAHO_REPLICAS:-1}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: pentaho-server
  template:
    metadata:
      labels:
        app: pentaho-server
        tier: application
        environment: ${ENVIRONMENT}
      annotations:
        # Force pod restart on config changes
        configmap/checksum: \$(kubectl get configmap pentaho-config -n ${K8S_NAMESPACE} -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || echo 'initial')
    spec:
      serviceAccountName: pentaho-service-account
      securityContext:
        fsGroup: 1000
      containers:
      - name: pentaho-server
        image: ${PENTAHO_ECR_IMAGE_URI}
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        - name: https
          containerPort: 8443
          protocol: TCP
        env:
        - name: PENTAHO_SERVER_NAME
          value: "${PENTAHO_SERVER_NAME}"
        - name: PENTAHO_BASE_URL
          value: "${PENTAHO_BASE_URL}"
        - name: JCR_DB_HOST
          valueFrom:
            secretKeyRef:
              name: pentaho-jcr-db
              key: host
        - name: JCR_DB_PORT
          valueFrom:
            secretKeyRef:
              name: pentaho-jcr-db
              key: port
        - name: JCR_DB_NAME
          valueFrom:
            secretKeyRef:
              name: pentaho-jcr-db
              key: database
        - name: JCR_DB_USER
          valueFrom:
            secretKeyRef:
              name: pentaho-jcr-db
              key: username
        - name: JCR_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pentaho-jcr-db
              key: password
        - name: QUARTZ_DB_HOST
          valueFrom:
            secretKeyRef:
              name: pentaho-quartz-db
              key: host
        - name: QUARTZ_DB_PORT
          valueFrom:
            secretKeyRef:
              name: pentaho-quartz-db
              key: port
        - name: QUARTZ_DB_NAME
          valueFrom:
            secretKeyRef:
              name: pentaho-quartz-db
              key: database
        - name: QUARTZ_DB_USER
          valueFrom:
            secretKeyRef:
              name: pentaho-quartz-db
              key: username
        - name: QUARTZ_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pentaho-quartz-db
              key: password
        - name: JAVA_OPTS
          value: "${JAVA_OPTS}"
        volumeMounts:
        - name: pentaho-data
          mountPath: /opt/pentaho/pentaho-server/pentaho-solutions/system/data
        - name: pentaho-logs
          mountPath: /opt/pentaho/pentaho-server/tomcat/logs
        - name: pentaho-config
          mountPath: /opt/pentaho/pentaho-server/pentaho-solutions/system/pentaho.xml
          subPath: pentaho.xml
        resources:
          requests:
            memory: "${MEMORY_REQUEST}"
            cpu: "${CPU_REQUEST}"
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
        livenessProbe:
          httpGet:
            path: /pentaho/
            port: 8080
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /pentaho/
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /pentaho/
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 10
      volumes:
      - name: pentaho-data
        persistentVolumeClaim:
          claimName: pentaho-data-pvc
      - name: pentaho-logs
        persistentVolumeClaim:
          claimName: pentaho-logs-pvc
      - name: pentaho-config
        configMap:
          name: pentaho-config
      restartPolicy: Always
      terminationGracePeriodSeconds: 60
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pentaho-config
  namespace: ${K8S_NAMESPACE}
data:
  pentaho.xml: |
    <?xml version="1.0" encoding="UTF-8"?>
    <pentaho-system>
      <log-level>INFO</log-level>
      <console-log>true</console-log>
      <repositories>
        <repository>
          <id>PentahoEnterpriseRepository</id>
          <name>Pentaho Enterprise Repository</name>
          <url>jdbc:postgresql://\${JCR_DB_HOST}:\${JCR_DB_PORT}/\${JCR_DB_NAME}</url>
          <username>\${JCR_DB_USER}</username>
          <password>\${JCR_DB_PASSWORD}</password>
        </repository>
      </repositories>
      <default-repository-id>PentahoEnterpriseRepository</default-repository-id>
    </pentaho-system>
EOF

    log_success "Pentaho deployment manifest generated"
}

# Function to generate service manifest
generate_service_manifest() {
    log_step "Generating Pentaho service manifest..."
    
    local service_file="kubernetes/pentaho-service.yaml"
    
    cat > "$service_file" << EOF
apiVersion: v1
kind: Service
metadata:
  name: pentaho-server-service
  namespace: ${K8S_NAMESPACE}
  labels:
    app: pentaho-server
    tier: application
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
spec:
  type: LoadBalancer
  selector:
    app: pentaho-server
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
  - name: https
    port: 443
    targetPort: 8443
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: pentaho-server-internal
  namespace: ${K8S_NAMESPACE}
  labels:
    app: pentaho-server
    tier: application
spec:
  type: ClusterIP
  selector:
    app: pentaho-server
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  - name: https
    port: 8443
    targetPort: 8443
    protocol: TCP
EOF

    log_success "Service manifest generated"
}

# Function to generate ingress manifest
generate_ingress_manifest() {
    log_step "Generating ingress manifest..."
    
    local ingress_file="kubernetes/pentaho-ingress.yaml"
    
    cat > "$ingress_file" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pentaho-ingress
  namespace: ${K8S_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /pentaho/
    alb.ingress.kubernetes.io/success-codes: "200,302"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
  - host: ${PENTAHO_HOSTNAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pentaho-server-internal
            port:
              number: 8080
EOF

    log_success "Ingress manifest generated"
}

# Function to create service account and RBAC
create_service_account() {
    log_step "Creating service account and RBAC..."
    
    local rbac_file="kubernetes/pentaho-rbac.yaml"
    
    cat > "$rbac_file" << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pentaho-service-account
  namespace: ${K8S_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ECR_ACCOUNT_ID}:role/${PROJECT_NAME}-${ENVIRONMENT}-pentaho-service-role
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${K8S_NAMESPACE}
  name: pentaho-role
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps", "pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pentaho-role-binding
  namespace: ${K8S_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: pentaho-service-account
  namespace: ${K8S_NAMESPACE}
roleRef:
  kind: Role
  name: pentaho-role
  apiGroup: rbac.authorization.k8s.io
EOF

    log_kube "Applying RBAC configuration..."
    kubectl apply -f "$rbac_file"
    
    log_success "Service account and RBAC configured"
}

# Function to deploy Pentaho
deploy_pentaho() {
    log_step "Deploying Pentaho to Kubernetes..."
    
    # Apply all manifests with environment variable substitution
    log_kube "Applying deployment manifest..."
    envsubst < kubernetes/pentaho-deployment.yaml | kubectl apply -f -
    
    log_kube "Applying service manifest..."
    envsubst < kubernetes/pentaho-service.yaml | kubectl apply -f -
    
    log_kube "Applying ingress manifest..."
    envsubst < kubernetes/pentaho-ingress.yaml | kubectl apply -f -
    
    log_success "Pentaho deployed successfully"
}

# Function to wait for deployment
wait_for_deployment() {
    log_step "Waiting for Pentaho deployment to be ready..."
    
    # Wait for deployment to be available
    if kubectl wait --for=condition=available --timeout=600s deployment/pentaho-server -n "$K8S_NAMESPACE"; then
        log_success "Pentaho deployment is ready"
    else
        log_error "Deployment failed to become ready within 10 minutes"
        log_info "Check deployment status:"
        kubectl get pods -n "$K8S_NAMESPACE"
        kubectl describe deployment pentaho-server -n "$K8S_NAMESPACE"
        return 1
    fi
    
    # Wait for at least one pod to be running
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local running_pods
        running_pods=$(kubectl get pods -n "$K8S_NAMESPACE" -l app=pentaho-server --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        
        if [ "$running_pods" -gt 0 ]; then
            log_success "Pentaho pods are running"
            break
        else
            log_info "Waiting for pods to start... (attempt $attempt/$max_attempts)"
            sleep 15
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Pods failed to start within expected time"
        return 1
    fi
}

# Function to get service endpoints
get_service_endpoints() {
    log_step "Retrieving service endpoints..."
    
    # Get LoadBalancer endpoint
    local max_attempts=10
    local attempt=1
    local lb_hostname=""
    
    while [ $attempt -le $max_attempts ] && [ -z "$lb_hostname" ]; do
        lb_hostname=$(kubectl get service pentaho-server-service -n "$K8S_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [ -z "$lb_hostname" ]; then
            log_info "Waiting for LoadBalancer endpoint... (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ -n "$lb_hostname" ]; then
        PENTAHO_LB_ENDPOINT="$lb_hostname"
        log_success "LoadBalancer endpoint: $PENTAHO_LB_ENDPOINT"
    else
        log_warning "LoadBalancer endpoint not yet available"
    fi
    
    # Get Ingress endpoint
    local ingress_hostname
    ingress_hostname=$(kubectl get ingress pentaho-ingress -n "$K8S_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$ingress_hostname" ]; then
        PENTAHO_INGRESS_ENDPOINT="$ingress_hostname"
        log_success "Ingress endpoint: $PENTAHO_INGRESS_ENDPOINT"
    else
        log_info "Ingress endpoint will be available shortly"
    fi
}

# Function to validate deployment
validate_deployment() {
    log_step "Validating deployment..."
    
    # Check pod status
    log_kube "Checking pod status..."
    kubectl get pods -n "$K8S_NAMESPACE" -l app=pentaho-server
    
    # Check service status
    log_kube "Checking service status..."
    kubectl get services -n "$K8S_NAMESPACE"
    
    # Check ingress status
    log_kube "Checking ingress status..."
    kubectl get ingress -n "$K8S_NAMESPACE"
    
    # Test internal connectivity if LoadBalancer is ready
    if [ -n "${PENTAHO_LB_ENDPOINT:-}" ]; then
        log_step "Testing Pentaho connectivity..."
        if curl -s --connect-timeout 10 "http://$PENTAHO_LB_ENDPOINT/pentaho/" >/dev/null; then
            log_success "Pentaho is responding to HTTP requests"
        else
            log_warning "Pentaho may still be starting up"
            log_info "Check pod logs: kubectl logs -n $K8S_NAMESPACE -l app=pentaho-server"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Function to update runtime state
update_runtime_state() {
    local env_name="$1"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    log_step "Updating runtime state..."
    
    cat >> "$runtime_file" << EOF

# Deployment Information - Updated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
PENTAHO_DEPLOYED=true
K8S_DEPLOYMENT_NAME=pentaho-server
K8S_SERVICE_NAME=pentaho-server-service
K8S_INGRESS_NAME=pentaho-ingress
PENTAHO_LB_ENDPOINT=${PENTAHO_LB_ENDPOINT:-""}
PENTAHO_INGRESS_ENDPOINT=${PENTAHO_INGRESS_ENDPOINT:-""}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log_success "Runtime state updated"
}

# Function to display summary
display_summary() {
    local env_name="$1"
    
    log_success "Pentaho deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    echo "  Environment: $env_name"
    echo "  Namespace: $K8S_NAMESPACE"
    echo "  Image: $PENTAHO_ECR_IMAGE_URI"
    echo "  Cluster: $EKS_CLUSTER_NAME"
    echo
    
    if [ -n "${PENTAHO_LB_ENDPOINT:-}" ]; then
        log_info "Access URLs:"
        echo "  HTTP:  http://$PENTAHO_LB_ENDPOINT/pentaho/"
        echo "  HTTPS: https://$PENTAHO_LB_ENDPOINT/pentaho/"
    fi
    
    if [ -n "${PENTAHO_INGRESS_ENDPOINT:-}" ]; then
        echo "  Custom: https://$PENTAHO_HOSTNAME/pentaho/"
    fi
    
    echo
    log_info "Useful Commands:"
    echo "  # Check pod status"
    echo "  kubectl get pods -n $K8S_NAMESPACE"
    echo
    echo "  # View pod logs"
    echo "  kubectl logs -n $K8S_NAMESPACE -l app=pentaho-server"
    echo
    echo "  # Get service info"
    echo "  kubectl get services -n $K8S_NAMESPACE"
    echo
    echo "  # Port forward for local access"
    echo "  kubectl port-forward -n $K8S_NAMESPACE service/pentaho-server-internal 8080:8080"
    echo
    
    log_info "Monitoring:"
    echo "  # Watch deployment"
    echo "  kubectl get pods -n $K8S_NAMESPACE -w"
    echo
    echo "  # Check resource usage"
    echo "  kubectl top pods -n $K8S_NAMESPACE"
}

# Main execution
main() {
    local env_name="${1:-}"
    
    echo "🚀 Pentaho AWS EKS Deployment"
    echo "============================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    
    log_info "Deploying Pentaho for environment: $env_name"
    log_info "Cluster: $EKS_CLUSTER_NAME"
    log_info "Namespace: $K8S_NAMESPACE"
    log_info "Image: $PENTAHO_ECR_IMAGE_URI"
    echo
    
    configure_kubectl
    setup_namespace
    
    generate_pentaho_deployment
    generate_service_manifest
    generate_ingress_manifest
    
    create_service_account
    deploy_pentaho
    
    wait_for_deployment
    get_service_endpoints
    validate_deployment
    
    update_runtime_state "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
