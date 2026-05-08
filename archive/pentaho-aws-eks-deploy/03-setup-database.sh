#!/bin/bash

# =============================================================================
# Pentaho AWS EKS Database Setup Script
# =============================================================================
# This script handles PostgreSQL database setup for Pentaho EKS deployment:
# - Connects to RDS PostgreSQL instance
# - Creates databases and users
# - Executes schema initialization scripts
# - Configures database connectivity

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
DATABASE="🗄️"
CONNECT="🔗"

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
log_db() { log "$CYAN" "$DATABASE $1"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    local missing_commands=()
    
    # Check required commands
    if ! command_exists psql; then missing_commands+=("postgresql-client (psql)"); fi
    if ! command_exists aws; then missing_commands+=("aws-cli"); fi
    if ! command_exists jq; then missing_commands+=("jq"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install PostgreSQL client: brew install postgresql"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not available."
        if [ -n "${AWS_PROFILE:-}" ]; then
            log_info "Please run: okta-aws $AWS_PROFILE sts get-caller-identity"
        else
            log_info "Please run: okta-aws yourprofile sts get-caller-identity"
        fi
        log_info "Then re-run this script"
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
        log_info "Please run: ./01-setup-infrastructure.sh $env_name first"
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
    
    log_success "Configuration loaded for environment: $env_name"
}

# Function to wait for RDS instance to be available
wait_for_rds() {
    log_step "Checking RDS instance availability..."
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status
        status=$(aws rds describe-db-instances \
            --db-instance-identifier "$RDS_DB_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "available" ]; then
            log_success "RDS instance is available"
            return 0
        elif [ "$status" = "not-found" ]; then
            log_error "RDS instance not found: $RDS_DB_INSTANCE_ID"
            return 1
        else
            log_info "RDS instance status: $status (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    log_error "RDS instance did not become available within expected time"
    return 1
}

# Function to get RDS endpoint
get_rds_endpoint() {
    log_step "Retrieving RDS endpoint..."
    
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" = "None" ]; then
        log_error "Could not retrieve RDS endpoint"
        return 1
    fi
    
    log_success "RDS endpoint: $RDS_ENDPOINT"
    return 0
}

# Function to test database connectivity
test_db_connectivity() {
    log_step "Testing database connectivity..."
    
    # Test connection with master user
    local PGPASSWORD="$RDS_MASTER_PASSWORD"
    export PGPASSWORD
    
    if psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "SELECT version();" >/dev/null 2>&1; then
        log_success "Database connection successful"
        unset PGPASSWORD
        return 0
    else
        log_error "Database connection failed"
        log_info "Endpoint: $RDS_ENDPOINT"
        log_info "User: $RDS_MASTER_USERNAME"
        log_info "Please check:"
        log_info "  - RDS security group allows connections from your IP"
        log_info "  - VPC and subnet configuration"
        log_info "  - Password is correct"
        unset PGPASSWORD
        return 1
    fi
}

# Function to create databases and users
create_databases_and_users() {
    log_step "Creating databases and users..."
    
    local PGPASSWORD="$RDS_MASTER_PASSWORD"
    export PGPASSWORD
    
    # Create databases
    log_db "Creating JCR database..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        CREATE DATABASE ${JCR_DB_NAME}
            WITH ENCODING='UTF8'
            LC_COLLATE='en_US.UTF-8'
            LC_CTYPE='en_US.UTF-8'
            TEMPLATE=template0;" 2>/dev/null || {
        log_warning "JCR database might already exist"
    }
    
    log_db "Creating Quartz database..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        CREATE DATABASE ${QUARTZ_DB_NAME}
            WITH ENCODING='UTF8'
            LC_COLLATE='en_US.UTF-8'
            LC_CTYPE='en_US.UTF-8'
            TEMPLATE=template0;" 2>/dev/null || {
        log_warning "Quartz database might already exist"
    }
    
    # Create JCR user
    log_db "Creating JCR database user..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        CREATE USER ${JCR_DB_USER} WITH PASSWORD '${JCR_DB_PASSWORD}';" 2>/dev/null || {
        log_warning "JCR user might already exist"
    }
    
    # Create Quartz user
    log_db "Creating Quartz database user..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        CREATE USER ${QUARTZ_DB_USER} WITH PASSWORD '${QUARTZ_DB_PASSWORD}';" 2>/dev/null || {
        log_warning "Quartz user might already exist"
    }
    
    # Grant permissions
    log_db "Granting JCR database permissions..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        GRANT ALL PRIVILEGES ON DATABASE ${JCR_DB_NAME} TO ${JCR_DB_USER};
        ALTER DATABASE ${JCR_DB_NAME} OWNER TO ${JCR_DB_USER};"
    
    log_db "Granting Quartz database permissions..."
    psql -h "$RDS_ENDPOINT" -p 5432 -U "$RDS_MASTER_USERNAME" -d postgres -c "
        GRANT ALL PRIVILEGES ON DATABASE ${QUARTZ_DB_NAME} TO ${QUARTZ_DB_USER};
        ALTER DATABASE ${QUARTZ_DB_NAME} OWNER TO ${QUARTZ_DB_USER};"
    
    unset PGPASSWORD
    log_success "Databases and users created successfully"
}

# Function to initialize JCR schema
initialize_jcr_schema() {
    log_step "Initializing JCR schema..."
    
    local jcr_schema_file="database/create_jcr_postgresql.sql"
    
    if [ ! -f "$jcr_schema_file" ]; then
        log_error "JCR schema file not found: $jcr_schema_file"
        return 1
    fi
    
    local PGPASSWORD="$JCR_DB_PASSWORD"
    export PGPASSWORD
    
    log_db "Executing JCR schema creation..."
    if psql -h "$RDS_ENDPOINT" -p 5432 -U "$JCR_DB_USER" -d "$JCR_DB_NAME" -f "$jcr_schema_file"; then
        log_success "JCR schema initialized successfully"
    else
        log_error "JCR schema initialization failed"
        unset PGPASSWORD
        return 1
    fi
    
    # Verify tables were created
    local table_count
    table_count=$(psql -h "$RDS_ENDPOINT" -p 5432 -U "$JCR_DB_USER" -d "$JCR_DB_NAME" -t -c "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" | xargs)
    
    if [ "$table_count" -gt 0 ]; then
        log_success "JCR tables created: $table_count tables"
    else
        log_warning "No JCR tables found after schema execution"
    fi
    
    unset PGPASSWORD
}

# Function to initialize Quartz schema
initialize_quartz_schema() {
    log_step "Initializing Quartz schema..."
    
    local quartz_schema_file="database/create_quartz_postgresql.sql"
    
    if [ ! -f "$quartz_schema_file" ]; then
        log_error "Quartz schema file not found: $quartz_schema_file"
        return 1
    fi
    
    local PGPASSWORD="$QUARTZ_DB_PASSWORD"
    export PGPASSWORD
    
    log_db "Executing Quartz schema creation..."
    if psql -h "$RDS_ENDPOINT" -p 5432 -U "$QUARTZ_DB_USER" -d "$QUARTZ_DB_NAME" -f "$quartz_schema_file"; then
        log_success "Quartz schema initialized successfully"
    else
        log_error "Quartz schema initialization failed"
        unset PGPASSWORD
        return 1
    fi
    
    # Verify tables were created
    local table_count
    table_count=$(psql -h "$RDS_ENDPOINT" -p 5432 -U "$QUARTZ_DB_USER" -d "$QUARTZ_DB_NAME" -t -c "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" | xargs)
    
    if [ "$table_count" -gt 0 ]; then
        log_success "Quartz tables created: $table_count tables"
    else
        log_warning "No Quartz tables found after schema execution"
    fi
    
    unset PGPASSWORD
}

# Function to create database connection secrets in Kubernetes
create_k8s_secrets() {
    log_step "Creating Kubernetes database secrets..."
    
    # Check if kubectl is configured for the cluster
    if ! kubectl get namespaces >/dev/null 2>&1; then
        log_error "kubectl not configured or cluster not accessible"
        log_info "Please configure kubectl: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
        return 1
    fi
    
    # Ensure namespace exists
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create JCR database secret
    log_db "Creating JCR database secret..."
    kubectl create secret generic pentaho-jcr-db \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=host="$RDS_ENDPOINT" \
        --from-literal=port="5432" \
        --from-literal=database="$JCR_DB_NAME" \
        --from-literal=username="$JCR_DB_USER" \
        --from-literal=password="$JCR_DB_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Quartz database secret
    log_db "Creating Quartz database secret..."
    kubectl create secret generic pentaho-quartz-db \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=host="$RDS_ENDPOINT" \
        --from-literal=port="5432" \
        --from-literal=database="$QUARTZ_DB_NAME" \
        --from-literal=username="$QUARTZ_DB_USER" \
        --from-literal=password="$QUARTZ_DB_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Kubernetes secrets created"
}

# Function to validate database setup
validate_database_setup() {
    log_step "Validating database setup..."
    
    # Test JCR connection
    local PGPASSWORD="$JCR_DB_PASSWORD"
    export PGPASSWORD
    
    local jcr_tables
    jcr_tables=$(psql -h "$RDS_ENDPOINT" -p 5432 -U "$JCR_DB_USER" -d "$JCR_DB_NAME" -t -c "
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" 2>/dev/null | wc -l | xargs)
    
    unset PGPASSWORD
    
    # Test Quartz connection
    PGPASSWORD="$QUARTZ_DB_PASSWORD"
    export PGPASSWORD
    
    local quartz_tables
    quartz_tables=$(psql -h "$RDS_ENDPOINT" -p 5432 -U "$QUARTZ_DB_USER" -d "$QUARTZ_DB_NAME" -t -c "
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" 2>/dev/null | wc -l | xargs)
    
    unset PGPASSWORD
    
    log_info "Database validation results:"
    log_info "  JCR Database: $jcr_tables tables"
    log_info "  Quartz Database: $quartz_tables tables"
    
    if [ "$jcr_tables" -gt 0 ] && [ "$quartz_tables" -gt 0 ]; then
        log_success "Database validation passed"
        return 0
    else
        log_error "Database validation failed"
        return 1
    fi
}

# Function to update runtime state with database information
update_runtime_state() {
    local env_name="$1"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    log_step "Updating runtime state..."
    
    # Add database information to runtime state
    cat >> "$runtime_file" << EOF

# Database Information - Updated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
RDS_ENDPOINT_RESOLVED=$RDS_ENDPOINT
JCR_DB_READY=true
QUARTZ_DB_READY=true
DB_SETUP_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log_success "Runtime state updated"
}

# Function to display summary
display_summary() {
    local env_name="$1"
    
    log_success "Database setup completed successfully!"
    echo
    log_info "Summary:"
    echo "  Environment: $env_name"
    echo "  RDS Endpoint: $RDS_ENDPOINT"
    echo "  JCR Database: $JCR_DB_NAME"
    echo "  Quartz Database: $QUARTZ_DB_NAME"
    echo "  Kubernetes Namespace: $K8S_NAMESPACE"
    echo
    log_info "Database Connection Details:"
    echo "  Host: $RDS_ENDPOINT"
    echo "  Port: 5432"
    echo "  JCR DB: $JCR_DB_NAME (user: $JCR_DB_USER)"
    echo "  Quartz DB: $QUARTZ_DB_NAME (user: $QUARTZ_DB_USER)"
    echo
    log_info "Next Steps:"
    echo "  1. Run: ./04-deploy-pentaho.sh $env_name"
    echo
    log_info "To connect to databases manually:"
    echo "  psql -h $RDS_ENDPOINT -p 5432 -U $JCR_DB_USER -d $JCR_DB_NAME"
    echo "  psql -h $RDS_ENDPOINT -p 5432 -U $QUARTZ_DB_USER -d $QUARTZ_DB_NAME"
}

# Main execution
main() {
    local env_name="${1:-}"
    
    echo "🗄️ Pentaho AWS EKS Database Setup"
    echo "=================================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    
    log_info "Setting up databases for environment: $env_name"
    log_info "RDS Instance: $RDS_DB_INSTANCE_ID"
    echo
    
    wait_for_rds
    get_rds_endpoint
    test_db_connectivity
    
    create_databases_and_users
    initialize_jcr_schema
    initialize_quartz_schema
    
    create_k8s_secrets
    validate_database_setup
    
    update_runtime_state "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
