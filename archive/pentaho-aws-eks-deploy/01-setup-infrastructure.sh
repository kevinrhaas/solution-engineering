#!/bin/bash

# ========================log_step() { log "$YELLOW" "$ARROW $1"; }

# Helper function to run AWS commands with profile
run_aws() {
    aws --profile "${AWS_PROFILE}" "$@"
}

# Function to check if a command exists==================================================
# Pentaho AWS EKS Infrastructure Setup Script
# =============================================================================
# This script creates the AWS infrastructure needed for Pentaho EKS deployment:
# - EKS cluster with worker nodes
# - RDS PostgreSQL instance
# - S3 bucket for persistent storage
# - ECR repository for Docker images
# - IAM roles and policies

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons for better UX
CHECK="✅"
ERROR="❌"
ARROW="➤"
INFO="ℹ️"
GEAR="⚙️"

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
    if ! command_exists aws; then missing_commands+=("aws-cli"); fi
    if ! command_exists eksctl; then missing_commands+=("eksctl"); fi
    if ! command_exists jq; then missing_commands+=("jq"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install missing tools:"
        log_info "  brew install kubectl awscli eksctl jq"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to validate AWS authentication
validate_aws_authentication() {
    log_step "Validating AWS authentication..."
    
    # Check AWS authentication via okta-aws
    if [ -n "${AWS_PROFILE:-}" ]; then
        log_info "Validating AWS credentials..."
        if ! aws --profile "$AWS_PROFILE" sts get-caller-identity >/dev/null 2>&1; then
            log_error "AWS credentials not available."
            log_info "Please run: okta-aws $AWS_PROFILE sts get-caller-identity"
            log_info "Then re-run this script"
            exit 1
        fi
        log_success "AWS credentials validated"
    else
        log_error "AWS_PROFILE not set in configuration"
        log_info "Please set AWS_PROFILE in your environment file"
        exit 1
    fi
    
    # Validate SSH key if specified
    if [ -n "${KEY_PATH:-}" ]; then
        if [ ! -f "$KEY_PATH" ]; then
            log_error "SSH key file not found: $KEY_PATH"
            exit 1
        else
            log_info "SSH key validated: $KEY_PATH"
        fi
    fi
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
    
    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        log_info "Create it from the sample: cp pentaho-eks-sample.env $env_file"
        exit 1
    fi
    
    log_step "Loading environment configuration from $env_file..."
    source "$env_file"
    
    # Set up AWS environment using okta-aws
    if [ -n "${AWS_PROFILE:-}" ]; then
        log_info "Setting up AWS credentials via okta-aws profile: $AWS_PROFILE"
        export AWS_PROFILE="$AWS_PROFILE"
    fi
    
    # Set environment-specific values
    CLUSTER_NAME="${CLUSTER_NAME}-${env_name}"
    DB_INSTANCE_IDENTIFIER="${DB_INSTANCE_IDENTIFIER}-${env_name}"
    S3_BUCKET_NAME="${S3_BUCKET_NAME}-${env_name}"
    ECR_REPOSITORY_NAME="${ECR_REPOSITORY_NAME}-${env_name}"
    
    log_success "Environment configuration loaded for: $ENVIRONMENT"
}

# Function to create EKS cluster
create_eks_cluster() {
    log_step "Creating EKS cluster: $CLUSTER_NAME..."
    
    # Check if cluster already exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_warning "EKS cluster '$CLUSTER_NAME' already exists"
        return 0
    fi
    
    # Create cluster using eksctl
    log_info "Creating EKS cluster (this may take 15-20 minutes)..."
    
    # Extract key name from key path (remove path and .pem extension)
    local key_name=""
    if [ -n "${KEY_PATH:-}" ]; then
        key_name=$(basename "$KEY_PATH" .pem)
        log_info "Using SSH key: $key_name"
    fi
    
    # Build eksctl command
    local eksctl_cmd="eksctl create cluster \
        --name $CLUSTER_NAME \
        --version $KUBERNETES_VERSION \
        --region $AWS_REGION \
        --nodegroup-name $NODE_GROUP_NAME \
        --node-type $NODE_INSTANCE_TYPE \
        --nodes $NODE_DESIRED_CAPACITY \
        --nodes-min $NODE_MIN_SIZE \
        --nodes-max $NODE_MAX_SIZE \
        --managed \
        --enable-ssm \
        --asg-access \
        --external-dns-access \
        --full-ecr-access \
        --alb-ingress-access"
    
    # Add SSH key if available
    if [ -n "$key_name" ]; then
        eksctl_cmd="$eksctl_cmd --ssh-access --ssh-public-key $key_name"
    fi
    
    # Add specific VPC/subnet if configured
    if [ -n "${VPC_ID:-}" ] && [ -n "${SUBNET_ID:-}" ]; then
        log_info "Using existing VPC: $VPC_ID and subnet: $SUBNET_ID"
        eksctl_cmd="$eksctl_cmd --vpc-private-subnets $SUBNET_ID"
    fi
    
    # Execute the command
    eval "$eksctl_cmd"
    
    # Update kubeconfig
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    
    log_success "EKS cluster created successfully"
}

# Function to create RDS PostgreSQL instance
create_rds_instance() {
    log_step "Creating RDS PostgreSQL instance: $DB_INSTANCE_IDENTIFIER..."
    
    # Check if instance already exists
    if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_warning "RDS instance '$DB_INSTANCE_IDENTIFIER' already exists"
        return 0
    fi
    
    # Get default VPC and subnets
    local vpc_id default_subnet_group
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")
    
    # Create DB subnet group if it doesn't exist
    local subnet_group_name="${DB_INSTANCE_IDENTIFIER}-subnet-group"
    if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$subnet_group_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating DB subnet group..."
        
        # Get subnets in default VPC
        local subnets
        subnets=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query "Subnets[*].SubnetId" \
            --output text \
            --region "$AWS_REGION" | tr '\t' ' ')
        
        aws rds create-db-subnet-group \
            --db-subnet-group-name "$subnet_group_name" \
            --db-subnet-group-description "Subnet group for Pentaho PostgreSQL" \
            --subnet-ids $subnets \
            --region "$AWS_REGION"
    fi
    
    # Create security group for RDS
    local security_group_name="${DB_INSTANCE_IDENTIFIER}-sg"
    local security_group_id
    
    if ! security_group_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$security_group_name" "Name=vpc-id,Values=$vpc_id" \
        --query "SecurityGroups[0].GroupId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null); then
        
        log_info "Creating security group for RDS..."
        security_group_id=$(aws ec2 create-security-group \
            --group-name "$security_group_name" \
            --description "Security group for Pentaho PostgreSQL" \
            --vpc-id "$vpc_id" \
            --region "$AWS_REGION" \
            --query "GroupId" \
            --output text)
        
        # Allow PostgreSQL access from VPC CIDR
        aws ec2 authorize-security-group-ingress \
            --group-id "$security_group_id" \
            --protocol tcp \
            --port "$DB_PORT" \
            --cidr "10.0.0.0/8" \
            --region "$AWS_REGION"
    fi
    
    # Create RDS instance
    log_info "Creating RDS PostgreSQL instance (this may take 10-15 minutes)..."
    
    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --db-instance-class "$DB_INSTANCE_CLASS" \
        --engine postgres \
        --engine-version "$DB_ENGINE_VERSION" \
        --master-username "$DB_USERNAME" \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage "$DB_ALLOCATED_STORAGE" \
        --storage-type "$DB_STORAGE_TYPE" \
        --port "$DB_PORT" \
        --db-subnet-group-name "$subnet_group_name" \
        --vpc-security-group-ids "$security_group_id" \
        --backup-retention-period 7 \
        --storage-encrypted \
        --region "$AWS_REGION"
    
    # Wait for instance to be available
    log_info "Waiting for RDS instance to become available..."
    aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region "$AWS_REGION"
    
    log_success "RDS PostgreSQL instance created successfully"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_step "Creating S3 bucket: $S3_BUCKET_NAME..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$S3_REGION" >/dev/null 2>&1; then
        log_warning "S3 bucket '$S3_BUCKET_NAME' already exists"
        return 0
    fi
    
    # Create S3 bucket
    if [ "$S3_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME"
    else
        aws s3api create-bucket \
            --bucket "$S3_BUCKET_NAME" \
            --region "$S3_REGION" \
            --create-bucket-configuration LocationConstraint="$S3_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET_NAME" \
        --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log_success "S3 bucket created successfully"
}

# Function to create ECR repository
create_ecr_repository() {
    log_step "Creating ECR repository: $ECR_REPOSITORY_NAME..."
    
    # Check if repository already exists
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$ECR_REGION" >/dev/null 2>&1; then
        log_warning "ECR repository '$ECR_REPOSITORY_NAME' already exists"
        return 0
    fi
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name "$ECR_REPOSITORY_NAME" \
        --region "$ECR_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE
    
    # Set lifecycle policy to manage image retention
    aws ecr put-lifecycle-policy \
        --repository-name "$ECR_REPOSITORY_NAME" \
        --region "$ECR_REGION" \
        --lifecycle-policy-text '{
            "rules": [
                {
                    "rulePriority": 1,
                    "description": "Keep last 10 images",
                    "selection": {
                        "tagStatus": "any",
                        "countType": "imageCountMoreThan",
                        "countNumber": 10
                    },
                    "action": {
                        "type": "expire"
                    }
                }
            ]
        }'
    
    log_success "ECR repository created successfully"
}

# Function to create runtime state file
create_runtime_state() {
    local env_name="$1"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    log_step "Creating runtime state file..."
    
    # Get EKS cluster endpoint
    local cluster_endpoint
    cluster_endpoint=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.endpoint" --output text)
    
    # Get RDS endpoint
    local db_endpoint
    db_endpoint=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region "$AWS_REGION" --query "DBInstances[0].Endpoint.Address" --output text)
    
    # Get ECR repository URI
    local ecr_uri
    ecr_uri=$(aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$ECR_REGION" --query "repositories[0].repositoryUri" --output text)
    
    # Generate runtime state file
    cat > "$runtime_file" << EOF
# =============================================================================
# Pentaho AWS EKS Runtime State - Generated $(date)
# =============================================================================
# This file contains runtime information for the deployment
# DO NOT COMMIT TO VERSION CONTROL

ENVIRONMENT=$env_name
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# EKS Cluster Information
EKS_CLUSTER_NAME=$CLUSTER_NAME
EKS_CLUSTER_ENDPOINT=$cluster_endpoint
EKS_CLUSTER_REGION=$AWS_REGION

# RDS Information
RDS_INSTANCE_ID=$DB_INSTANCE_IDENTIFIER
RDS_ENDPOINT=$db_endpoint
RDS_PORT=$DB_PORT
RDS_USERNAME=$DB_USERNAME

# S3 Information
S3_BUCKET=$S3_BUCKET_NAME
S3_REGION=$S3_REGION

# ECR Information
ECR_REPOSITORY=$ECR_REPOSITORY_NAME
ECR_REPOSITORY_URI=$ecr_uri
ECR_REGION=$ECR_REGION

# Generated Connection Strings
DATABASE_URL=postgresql://$DB_USERNAME:$DB_PASSWORD@$db_endpoint:$DB_PORT/postgres
KUBECONFIG_CONTEXT=arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME
EOF

    log_success "Runtime state file created: $runtime_file"
}

# Function to display deployment summary
display_summary() {
    local env_name="$1"
    
    log_success "Infrastructure setup completed successfully!"
    echo
    log_info "Deployment Summary:"
    echo "  Environment: $env_name"
    echo "  EKS Cluster: $CLUSTER_NAME"
    echo "  RDS Instance: $DB_INSTANCE_IDENTIFIER"
    echo "  S3 Bucket: $S3_BUCKET_NAME"
    echo "  ECR Repository: $ECR_REPOSITORY_NAME"
    echo
    log_info "Next Steps:"
    echo "  1. Run: ./02-prepare-images.sh $env_name"
    echo "  2. Run: ./03-setup-database.sh $env_name"
    echo "  3. Run: ./04-deploy-pentaho.sh $env_name"
    echo
    log_info "To check cluster access:"
    echo "  kubectl get nodes"
    echo "  kubectl get namespaces"
}

# Main execution
main() {
    local env_name="${1:-}"
    
    echo "🚀 Pentaho AWS EKS Infrastructure Setup"
    echo "======================================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    validate_aws_authentication
    
    log_info "Setting up infrastructure for environment: $env_name"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Profile: $AWS_PROFILE"
    echo
    
    create_eks_cluster
    create_rds_instance
    create_s3_bucket
    create_ecr_repository
    
    create_runtime_state "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
