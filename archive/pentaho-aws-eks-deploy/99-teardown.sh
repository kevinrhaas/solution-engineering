#!/bin/bash

# =============================================================================
# Pentaho AWS EKS Teardown Script
# =============================================================================
# This script safely tears down the complete Pentaho EKS environment:
# - Removes Kubernetes resources
# - Deletes EKS cluster and node groups
# - Removes RDS instances
# - Cleans up S3 buckets and ECR repositories
# - Removes IAM roles and policies
# - Cleans up VPC and networking components

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
WARNING="⚠️"
DESTROY="💥"
CLEANUP="🧹"

# Function to print colored output
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_info() { log "$BLUE" "$INFO $1"; }
log_success() { log "$GREEN" "$CHECK $1"; }
log_warning() { log "$YELLOW" "$WARNING $1"; }
log_error() { log "$RED" "$ERROR $1"; }
log_step() { log "$YELLOW" "$ARROW $1"; }
log_destroy() { log "$RED" "$DESTROY $1"; }

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
    if ! command_exists eksctl; then missing_commands+=("eksctl"); fi
    if ! command_exists jq; then missing_commands+=("jq"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
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
        echo "Usage: $0 <environment> [--force]"
        echo "Example: $0 dev"
        exit 1
    fi
    
    local env_file="pentaho-eks-${env_name}.env"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        log_info "Nothing to tear down for environment: $env_name"
        exit 0
    fi
    
    log_step "Loading configuration..."
    source "$env_file"
    
    # Set up AWS environment using okta-aws
    if [ -n "${AWS_PROFILE:-}" ]; then
        log_info "Setting up AWS credentials via okta-aws profile: $AWS_PROFILE"
        eval "$(okta-aws "$AWS_PROFILE" env)"
        export AWS_PROFILE="$AWS_PROFILE"
    fi
    
    # Load runtime state if available
    if [ -f "$runtime_file" ]; then
        source "$runtime_file"
        log_info "Runtime state loaded"
    else
        log_warning "Runtime state file not found - some resources may not be tracked"
    fi
    
    log_success "Configuration loaded for environment: $env_name"
}

# Function to confirm destructive action
confirm_teardown() {
    local env_name="$1"
    local force="${2:-false}"
    
    if [ "$force" != "--force" ]; then
        echo
        log_warning "This will PERMANENTLY DELETE all resources for environment: $env_name"
        log_warning "This includes:"
        echo "  - EKS Cluster: ${EKS_CLUSTER_NAME:-unknown}"
        echo "  - RDS Instance: ${RDS_DB_INSTANCE_ID:-unknown}"
        echo "  - S3 Bucket: ${S3_BUCKET_NAME:-unknown}"
        echo "  - ECR Repository: ${ECR_REPOSITORY_NAME:-unknown}"
        echo "  - All associated networking and IAM resources"
        echo
        log_warning "This action CANNOT be undone!"
        echo
        
        read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
        
        if [ "$confirmation" != "DELETE" ]; then
            log_info "Teardown cancelled"
            exit 0
        fi
    fi
    
    log_destroy "Proceeding with teardown of environment: $env_name"
}

# Function to cleanup Kubernetes resources
cleanup_kubernetes() {
    log_step "Cleaning up Kubernetes resources..."
    
    # Configure kubectl if possible
    if [ -n "${EKS_CLUSTER_NAME:-}" ]; then
        if aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
            log_info "kubectl configured for cluster: $EKS_CLUSTER_NAME"
            
            # Delete Pentaho namespace and all resources
            if [ -n "${K8S_NAMESPACE:-}" ]; then
                log_destroy "Deleting namespace: $K8S_NAMESPACE"
                kubectl delete namespace "$K8S_NAMESPACE" --ignore-not-found=true --timeout=300s
            fi
            
            # Delete monitoring resources
            log_destroy "Deleting monitoring resources..."
            kubectl delete namespace monitoring --ignore-not-found=true --timeout=300s
            
            # Delete any remaining resources
            kubectl delete all --all --ignore-not-found=true --timeout=300s
            
        else
            log_warning "Could not configure kubectl - cluster may already be deleted"
        fi
    fi
    
    log_success "Kubernetes resources cleaned up"
}

# Function to delete EKS cluster
delete_eks_cluster() {
    log_step "Deleting EKS cluster..."
    
    if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
        log_warning "EKS cluster name not found in configuration"
        return 0
    fi
    
    # Check if cluster exists
    if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_destroy "Deleting EKS cluster: $EKS_CLUSTER_NAME"
        
        # Use eksctl for clean deletion
        if eksctl delete cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --wait; then
            log_success "EKS cluster deleted successfully"
        else
            log_error "Failed to delete EKS cluster with eksctl"
            
            # Fallback to manual deletion
            log_warning "Attempting manual cluster deletion..."
            
            # Delete node groups first
            local node_groups
            node_groups=$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups[]' --output text 2>/dev/null || echo "")
            
            for node_group in $node_groups; do
                log_destroy "Deleting node group: $node_group"
                aws eks delete-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$node_group" --region "$AWS_REGION" --no-cli-pager
            done
            
            # Wait for node groups to be deleted
            for node_group in $node_groups; do
                log_info "Waiting for node group deletion: $node_group"
                aws eks wait nodegroup-deleted --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$node_group" --region "$AWS_REGION"
            done
            
            # Delete cluster
            aws eks delete-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --no-cli-pager
            aws eks wait cluster-deleted --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
            
            log_success "EKS cluster deleted manually"
        fi
    else
        log_info "EKS cluster not found or already deleted"
    fi
}

# Function to delete RDS instance
delete_rds_instance() {
    log_step "Deleting RDS instance..."
    
    if [ -z "${RDS_DB_INSTANCE_ID:-}" ]; then
        log_warning "RDS instance ID not found in configuration"
        return 0
    fi
    
    # Check if RDS instance exists
    if aws rds describe-db-instances --db-instance-identifier "$RDS_DB_INSTANCE_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_destroy "Deleting RDS instance: $RDS_DB_INSTANCE_ID"
        
        # Delete without final snapshot for dev environments
        if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "test" ]]; then
            aws rds delete-db-instance \
                --db-instance-identifier "$RDS_DB_INSTANCE_ID" \
                --skip-final-snapshot \
                --delete-automated-backups \
                --region "$AWS_REGION" \
                --no-cli-pager
        else
            # Create final snapshot for prod environments
            local snapshot_id="${RDS_DB_INSTANCE_ID}-final-snapshot-$(date +%Y%m%d%H%M%S)"
            log_info "Creating final snapshot: $snapshot_id"
            
            aws rds delete-db-instance \
                --db-instance-identifier "$RDS_DB_INSTANCE_ID" \
                --final-db-snapshot-identifier "$snapshot_id" \
                --delete-automated-backups \
                --region "$AWS_REGION" \
                --no-cli-pager
        fi
        
        log_info "Waiting for RDS instance deletion..."
        aws rds wait db-instance-deleted --db-instance-identifier "$RDS_DB_INSTANCE_ID" --region "$AWS_REGION"
        log_success "RDS instance deleted"
    else
        log_info "RDS instance not found or already deleted"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_step "Deleting S3 bucket..."
    
    if [ -z "${S3_BUCKET_NAME:-}" ]; then
        log_warning "S3 bucket name not found in configuration"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        log_destroy "Deleting S3 bucket: $S3_BUCKET_NAME"
        
        # Empty bucket first
        log_info "Emptying S3 bucket..."
        aws s3 rm "s3://$S3_BUCKET_NAME" --recursive --region "$AWS_REGION"
        
        # Delete bucket
        aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION"
        log_success "S3 bucket deleted"
    else
        log_info "S3 bucket not found or already deleted"
    fi
}

# Function to delete ECR repository
delete_ecr_repository() {
    log_step "Deleting ECR repository..."
    
    if [ -z "${ECR_REPOSITORY_NAME:-}" ]; then
        log_warning "ECR repository name not found in configuration"
        return 0
    fi
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$ECR_REGION" >/dev/null 2>&1; then
        log_destroy "Deleting ECR repository: $ECR_REPOSITORY_NAME"
        
        # Delete repository and all images
        aws ecr delete-repository \
            --repository-name "$ECR_REPOSITORY_NAME" \
            --region "$ECR_REGION" \
            --force \
            --no-cli-pager
        
        log_success "ECR repository deleted"
    else
        log_info "ECR repository not found or already deleted"
    fi
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log_step "Deleting IAM roles and policies..."
    
    local project_name="${PROJECT_NAME:-pentaho-eks}"
    local environment="${ENVIRONMENT:-dev}"
    
    # List of IAM roles to delete (common patterns)
    local iam_roles=(
        "${project_name}-${environment}-cluster-role"
        "${project_name}-${environment}-node-role" 
        "${project_name}-${environment}-pentaho-service-role"
        "eksctl-${EKS_CLUSTER_NAME:-cluster}-cluster-ServiceRole"
        "eksctl-${EKS_CLUSTER_NAME:-cluster}-nodegroup-NodeInstanceRole"
    )
    
    for role in "${iam_roles[@]}"; do
        if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
            log_destroy "Deleting IAM role: $role"
            
            # Detach policies first
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name"
            done
            
            # Delete role
            aws iam delete-role --role-name "$role"
            log_info "Deleted IAM role: $role"
        fi
    done
    
    log_success "IAM resources cleaned up"
}

# Function to delete security groups and VPC resources
cleanup_vpc_resources() {
    log_step "Cleaning up VPC and security group resources..."
    
    if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
        log_warning "EKS cluster name not found - cannot identify VPC resources"
        return 0
    fi
    
    # Find security groups by cluster name tag
    local sg_ids
    sg_ids=$(aws ec2 describe-security-groups \
        --filters "Name=tag:kubernetes.io/cluster/${EKS_CLUSTER_NAME},Values=owned" \
        --query 'SecurityGroups[].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    for sg_id in $sg_ids; do
        if [ -n "$sg_id" ]; then
            log_destroy "Deleting security group: $sg_id"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null || {
                log_warning "Could not delete security group $sg_id (may have dependencies)"
            }
        fi
    done
    
    log_success "VPC resources cleanup completed"
}

# Function to cleanup local files
cleanup_local_files() {
    log_step "Cleaning up local configuration files..."
    
    local env_name="$1"
    local files_to_remove=(
        "pentaho-eks-${env_name}-runtime.state"
        "kubernetes/pentaho-deployment.yaml"
        "kubernetes/pentaho-service.yaml"
        "kubernetes/pentaho-ingress.yaml"
        "kubernetes/pentaho-rbac.yaml"
        "monitoring/"
        "scripts/"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            log_destroy "Removing: $file"
            rm -rf "$file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to display summary
display_summary() {
    local env_name="$1"
    
    log_success "Teardown completed for environment: $env_name"
    echo
    log_info "Resources that were cleaned up:"
    echo "  - Kubernetes resources and namespace"
    echo "  - EKS cluster and node groups"
    echo "  - RDS database instance"
    echo "  - S3 storage bucket"
    echo "  - ECR container repository"
    echo "  - IAM roles and policies"
    echo "  - Security groups and VPC resources"
    echo "  - Local configuration files"
    echo
    
    log_info "Manual verification recommended:"
    echo "  # Check for any remaining EKS resources"
    echo "  aws eks list-clusters --region $AWS_REGION"
    echo
    echo "  # Check for any remaining RDS instances"
    echo "  aws rds describe-db-instances --region $AWS_REGION"
    echo
    echo "  # Check for any remaining S3 buckets"
    echo "  aws s3api list-buckets --query 'Buckets[?contains(Name, \`$env_name\`)].Name'"
    echo
    echo "  # Check AWS costs"
    echo "  aws ce get-cost-and-usage --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics BlendedCost"
}

# Main execution
main() {
    local env_name="${1:-}"
    local force="${2:-}"
    
    echo "💥 Pentaho AWS EKS Teardown"
    echo "==========================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    confirm_teardown "$env_name" "$force"
    
    log_info "Beginning teardown of environment: $env_name"
    echo
    
    # Cleanup in reverse order of creation
    cleanup_kubernetes
    delete_eks_cluster
    delete_rds_instance
    delete_s3_bucket
    delete_ecr_repository
    delete_iam_resources
    cleanup_vpc_resources
    cleanup_local_files "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
