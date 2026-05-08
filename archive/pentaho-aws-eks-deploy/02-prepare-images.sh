#!/bin/bash

# =============================================================================
# Pentaho AWS EKS Image Preparation Script
# =============================================================================
# This script handles Docker image preparation for Pentaho EKS deployment:
# - Downloads pre-built Pentaho images from Hitachi Vantara registry
# - Tags images for ECR compatibility
# - Authenticates with ECR and pushes images
# - Validates image availability and integrity

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
DOCKER="🐳"
UPLOAD="⬆️"

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
log_docker() { log "$CYAN" "$DOCKER $1"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    local missing_commands=()
    
    # Check required commands
    if ! command_exists docker; then missing_commands+=("docker"); fi
    if ! command_exists aws; then missing_commands+=("aws-cli"); fi
    if ! command_exists jq; then missing_commands+=("jq"); fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start Docker."
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
    
    # Set environment-specific values
    ECR_REPOSITORY_NAME="${ECR_REPOSITORY_NAME}-${env_name}"
    
    log_success "Configuration loaded for environment: $env_name"
    
    # Display token status for user awareness
    if [ -n "${HITACHI_ARTIFACTORY_TOKEN:-}" ]; then
        log_info "Hitachi Vantara Artifactory token: ✅ Available"
    else
        log_warning "Hitachi Vantara Artifactory token: ❌ Not set"
        log_info "For automatic download, set: export HITACHI_ARTIFACTORY_TOKEN=your-token"
        log_info "Token can be generated at: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/"
    fi
}

# Function to authenticate with ECR
authenticate_ecr() {
    log_step "Authenticating with AWS ECR..."
    
    # Get ECR login token and authenticate Docker
    aws ecr get-login-password --region "$ECR_REGION" | \
        docker login --username AWS --password-stdin "$ECR_ACCOUNT_ID.dkr.ecr.$ECR_REGION.amazonaws.com"
    
    if [ $? -eq 0 ]; then
        log_success "ECR authentication successful"
    else
        log_error "ECR authentication failed"
        exit 1
    fi
}

# Function to check for local Pentaho images
check_local_images() {
    log_step "Checking for local Pentaho images..."
    
    local image_pattern="pentaho.*server.*${PENTAHO_VERSION}"
    local found_images
    
    found_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "$image_pattern" || true)
    
    if [ -z "$found_images" ]; then
        log_warning "No local Pentaho images found matching version $PENTAHO_VERSION"
        log_info "Please download and load the image first:"
        log_info "  1. Download from: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/"
        log_info "  2. Load image: docker load -i pentaho-server-${PENTAHO_VERSION}.tar.gz"
        return 1
    else
        log_success "Found local Pentaho images:"
        echo "$found_images" | while read -r image; do
            log_info "  - $image"
        done
        
        # Set the first found image as our source
        SOURCE_IMAGE=$(echo "$found_images" | head -n1)
        log_info "Using source image: $SOURCE_IMAGE"
    fi
    
    return 0
}

# Function to download Pentaho image from Hitachi Vantara Artifactory
download_pentaho_image_from_artifactory() {
    log_step "Downloading Pentaho image from Hitachi Vantara Artifactory..."
    
    # Check if HITACHI_ARTIFACTORY_TOKEN is set
    if [ -z "${HITACHI_ARTIFACTORY_TOKEN:-}" ]; then
        log_error "HITACHI_ARTIFACTORY_TOKEN environment variable not set"
        log_info "Please set the token from: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/"
        log_info "Generate a token and set: export HITACHI_ARTIFACTORY_TOKEN=your-token"
        return 1
    fi
    
    local image_filename="pentaho-server-${PENTAHO_VERSION}.tar.gz"
    local download_url="https://one.hitachivantara.com/artifactory/pdc-generic-release/pentaho/pdc-docker-deployment/release-v10.2.7/pdc-10.2.7-rc.1-images.tgz"
    
    # For version 11.0.0.0, construct the appropriate URL
    if [[ "$PENTAHO_VERSION" == 11.* ]]; then
        download_url="https://one.hitachivantara.com/artifactory/pdc-generic-release/pentaho/pdc-docker-deployment/release-v${PENTAHO_VERSION}/${image_filename}"
    fi
    
    log_info "Downloading from: $download_url"
    log_info "Image filename: $image_filename"
    
    # Download the image using curl with the token
    if curl -L \
        -H "Authorization: Bearer ${HITACHI_ARTIFACTORY_TOKEN}" \
        -o "$image_filename" \
        "$download_url"; then
        log_success "Successfully downloaded: $image_filename"
    else
        log_error "Failed to download Pentaho image from Artifactory"
        log_info "Please verify:"
        log_info "  1. Token is valid and not expired"
        log_info "  2. URL is correct for version $PENTAHO_VERSION"
        log_info "  3. Network connectivity to one.hitachivantara.com"
        return 1
    fi
    
    # Load the downloaded image
    log_docker "Loading Docker image from $image_filename..."
    if docker load -i "$image_filename"; then
        log_success "Successfully loaded Docker image"
        
        # Find the loaded image name
        SOURCE_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "pentaho.*server.*${PENTAHO_VERSION}" | head -n1)
        if [ -n "$SOURCE_IMAGE" ]; then
            log_success "Loaded image: $SOURCE_IMAGE"
        else
            log_warning "Could not automatically detect loaded image name"
            log_info "Available images:"
            docker images | grep pentaho
        fi
        
        # Clean up downloaded file
        rm -f "$image_filename"
        log_info "Cleaned up downloaded file"
        
        return 0
    else
        log_error "Failed to load Docker image"
        return 1
    fi
}

# Function to download Pentaho image (fallback methods)
download_pentaho_image() {
    log_step "Attempting to obtain Pentaho image..."
    
    # First try direct download from Hitachi Vantara Artifactory
    if download_pentaho_image_from_artifactory; then
        return 0
    fi
    
    log_warning "Artifactory download failed, trying registry pull..."
    
    # Try different possible image names/registries as fallback
    local possible_images=(
        "pentaho/pentaho-server:${PENTAHO_VERSION}"
        "${HV_DOCKER_REGISTRY:-registry.hitachivantara.com}/pentaho-server:${PENTAHO_VERSION}"
        "${JFROG_DOCKER_REGISTRY:-hitachivantara.jfrog.io}/pentaho-server:${PENTAHO_VERSION}"
    )
    
    for image in "${possible_images[@]}"; do
        log_info "Trying to pull: $image"
        if docker pull "$image" 2>/dev/null; then
            SOURCE_IMAGE="$image"
            log_success "Successfully pulled image: $image"
            return 0
        else
            log_warning "Failed to pull: $image"
        fi
    done
    
    log_error "Could not obtain Pentaho image via any method"
    log_info "Manual options:"
    log_info "  1. Download from: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/"
    log_info "  2. Load image: docker load -i pentaho-server-${PENTAHO_VERSION}.tar.gz"
    log_info "  3. Set HITACHI_ARTIFACTORY_TOKEN and retry"
    return 1
}

# Function to tag image for ECR
tag_for_ecr() {
    log_step "Tagging image for ECR..."
    
    local source_tag="$1"
    ECR_IMAGE_URI="${ECR_REPOSITORY_URI}:${PENTAHO_VERSION}"
    ECR_IMAGE_LATEST="${ECR_REPOSITORY_URI}:latest"
    
    log_docker "Tagging $source_tag -> $ECR_IMAGE_URI"
    docker tag "$source_tag" "$ECR_IMAGE_URI"
    
    log_docker "Tagging $source_tag -> $ECR_IMAGE_LATEST"  
    docker tag "$source_tag" "$ECR_IMAGE_LATEST"
    
    log_success "Image tagged successfully"
}

# Function to push images to ECR
push_to_ecr() {
    log_step "Pushing images to ECR..."
    
    log_docker "Pushing $ECR_IMAGE_URI..."
    if docker push "$ECR_IMAGE_URI"; then
        log_success "Successfully pushed versioned image"
    else
        log_error "Failed to push versioned image"
        return 1
    fi
    
    log_docker "Pushing $ECR_IMAGE_LATEST..."
    if docker push "$ECR_IMAGE_LATEST"; then
        log_success "Successfully pushed latest image"
    else
        log_error "Failed to push latest image"
        return 1
    fi
    
    return 0
}

# Function to verify image in ECR
verify_ecr_images() {
    log_step "Verifying images in ECR..."
    
    # Check if images exist in ECR
    local images
    images=$(aws ecr describe-images \
        --repository-name "$ECR_REPOSITORY_NAME" \
        --region "$ECR_REGION" \
        --query 'imageDetails[*].imageTags[]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$images" ]; then
        log_error "No images found in ECR repository"
        return 1
    fi
    
    log_success "Images found in ECR:"
    echo "$images" | tr '\t' '\n' | while read -r tag; do
        [ -n "$tag" ] && log_info "  - $ECR_REPOSITORY_URI:$tag"
    done
    
    # Get image sizes
    local image_details
    image_details=$(aws ecr describe-images \
        --repository-name "$ECR_REPOSITORY_NAME" \
        --region "$ECR_REGION" \
        --query 'imageDetails[*].[imageTags[0],imageSizeInBytes]' \
        --output text 2>/dev/null)
    
    if [ -n "$image_details" ]; then
        log_info "Image sizes:"
        echo "$image_details" | while IFS=$'\t' read -r tag size; do
            if [ -n "$tag" ] && [ -n "$size" ]; then
                local size_mb=$((size / 1024 / 1024))
                log_info "  - $tag: ${size_mb} MB"
            fi
        done
    fi
    
    return 0
}

# Function to clean up local images (optional)
cleanup_local_images() {
    local cleanup="${1:-false}"
    
    if [ "$cleanup" = "true" ]; then
        log_step "Cleaning up local tagged images..."
        
        # Remove ECR-tagged images (keep original)
        docker rmi "$ECR_IMAGE_URI" "$ECR_IMAGE_LATEST" 2>/dev/null || true
        
        log_success "Local cleanup completed"
    fi
}

# Function to update runtime state with image information
update_runtime_state() {
    local env_name="$1"
    local runtime_file="pentaho-eks-${env_name}-runtime.state"
    
    log_step "Updating runtime state..."
    
    # Add image information to runtime state
    cat >> "$runtime_file" << EOF

# Image Information - Updated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
PENTAHO_SOURCE_IMAGE=$SOURCE_IMAGE
PENTAHO_ECR_IMAGE_URI=$ECR_IMAGE_URI
PENTAHO_ECR_IMAGE_LATEST=$ECR_IMAGE_LATEST
PENTAHO_VERSION_DEPLOYED=$PENTAHO_VERSION
ECR_PUSH_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log_success "Runtime state updated"
}

# Function to display summary
display_summary() {
    local env_name="$1"
    
    log_success "Image preparation completed successfully!"
    echo
    log_info "Summary:"
    echo "  Environment: $env_name"
    echo "  Source Image: $SOURCE_IMAGE"
    echo "  ECR Repository: $ECR_REPOSITORY_URI"
    echo "  Pentaho Version: $PENTAHO_VERSION"
    echo
    log_info "Images available in ECR:"
    echo "  - $ECR_IMAGE_URI"
    echo "  - $ECR_IMAGE_LATEST"
    echo
    log_info "Next Steps:"
    echo "  1. Run: ./03-setup-database.sh $env_name"
    echo "  2. Run: ./04-deploy-pentaho.sh $env_name"
    echo
    log_info "To verify ECR images:"
    echo "  aws ecr describe-images --repository-name $ECR_REPOSITORY_NAME --region $ECR_REGION"
}

# Main execution
main() {
    local env_name="${1:-}"
    local cleanup_local="${2:-false}"
    
    echo "🐳 Pentaho AWS EKS Image Preparation"
    echo "===================================="
    echo
    
    validate_prerequisites
    load_environment "$env_name"
    
    log_info "Preparing images for environment: $env_name"
    log_info "ECR Repository: $ECR_REPOSITORY_URI"
    log_info "Pentaho Version: $PENTAHO_VERSION"
    echo
    
    authenticate_ecr
    
    # Try to find local images first, then download if needed
    if ! check_local_images; then
        if ! download_pentaho_image; then
            log_error "Could not obtain Pentaho image"
            exit 1
        fi
    fi
    
    tag_for_ecr "$SOURCE_IMAGE"
    push_to_ecr
    verify_ecr_images
    
    cleanup_local_images "$cleanup_local"
    update_runtime_state "$env_name"
    
    echo
    display_summary "$env_name"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
