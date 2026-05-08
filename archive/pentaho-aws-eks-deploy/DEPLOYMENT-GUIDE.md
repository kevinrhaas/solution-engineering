# Pentaho AWS EKS Deployment Guide 🧪

> ## ⚠️ **EXPERIMENTAL DEPLOYMENT - PROCEED WITH CAUTION** ⚠️
> 
> **This deployment system is experimental and under active development.**
> 
> - 🚨 **NOT SUITABLE FOR PRODUCTION ENVIRONMENTS**
> - ⚠️ **May fail due to insufficient AWS permissions**
> - 🔧 **Scripts may require manual intervention**
> - 💸 **AWS resources created will incur costs**
> - 🐛 **Unexpected behavior may occur**
> 
> **Only proceed if you:**
> - ✅ Understand the risks and limitations
> - ✅ Have appropriate AWS permissions for EKS, RDS, S3, ECR
> - ✅ Are comfortable troubleshooting AWS and Kubernetes issues
> - ✅ Accept responsibility for any AWS charges incurred

---

This guide provides step-by-step instructions for deploying Pentaho Server on Amazon EKS using the automated scripts in this project.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment Process](#detailed-deployment-process)
- [Configuration](#configuration)
- [Monitoring and Management](#monitoring-and-management)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Prerequisites

### Required Tools
Ensure you have the following tools installed:

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# kubectl
brew install kubectl

# eksctl
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Helm
brew install helm

# Docker
brew install --cask docker

# jq for JSON processing
brew install jq

# gettext for envsubst
brew install gettext
```

### AWS Authentication
Authenticate with AWS using your organization's SSO:

```bash
# For Pentaho/Hitachi Vantara users
okta-aws yourprofile sts get-caller-identity

# Verify authentication
aws sts get-caller-identity
```

### Hitachi Vantara Artifactory Token
For automatic Pentaho image download, you'll need an Artifactory token:

1. **Generate Token:**
   - Visit: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/
   - Click "Set Me Up" → Select "Docker" client
   - Click "Generate Token & Create Instructions"
   - Copy the generated token

2. **Set Environment Variable:**
   ```bash
   export HITACHI_ARTIFACTORY_TOKEN=your-generated-token-here
   ```

3. **Verify Token (Optional):**
   ```bash
   curl -H "Authorization: Bearer ${HITACHI_ARTIFACTORY_TOKEN}" \
        https://one.hitachivantara.com/artifactory/api/system/ping
   ```

**Note:** The token is only required for automatic image download. You can also manually download images from the portal and load them using `docker load -i pentaho-server-11.0.0.0-xxx.tar.gz`.

### Required AWS Permissions
Your AWS user/role needs permissions for:
- EKS cluster management
- EC2 instance and VPC management
- RDS instance management
- S3 bucket operations
- ECR repository management
- IAM role and policy management
- CloudWatch logs and metrics

## Quick Start

For a complete deployment with default settings:

```bash
# 1. Copy and customize configuration
cp pentaho-eks-sample.env pentaho-eks-dev.env
# Edit pentaho-eks-dev.env with your settings

# 2. Run complete deployment
./01-setup-infrastructure.sh dev
./02-prepare-images.sh dev
./03-setup-database.sh dev
./04-deploy-pentaho.sh dev
./05-monitoring-setup.sh dev
```

This will create a complete Pentaho environment with monitoring in approximately 20-30 minutes.

## Detailed Deployment Process

### Step 1: Infrastructure Setup

```bash
./01-setup-infrastructure.sh dev
```

**What this does:**
- Creates EKS cluster with managed node groups
- Sets up RDS PostgreSQL instance for Pentaho databases
- Creates S3 bucket for persistent storage
- Creates ECR repository for container images
- Configures VPC, subnets, and security groups
- Sets up IAM roles and policies

**Expected time:** 15-20 minutes

**Verification:**
```bash
# Check EKS cluster
aws eks describe-cluster --name pentaho-eks-dev --region us-west-2

# Check RDS instance
aws rds describe-db-instances --db-instance-identifier pentaho-rds-dev --region us-west-2

# Check S3 bucket
aws s3 ls pentaho-eks-dev-storage-bucket
```

### Step 2: Image Preparation

```bash
./02-prepare-images.sh dev
```

**What this does:**
- Authenticates with AWS ECR
- Downloads/pulls Pentaho Docker images using multiple methods:
  1. **Automatic Download:** Uses Hitachi Vantara Artifactory token for direct download
  2. **Registry Pull:** Attempts to pull from various Docker registries
  3. **Manual Load:** Instructions for manual image loading
- Tags images for ECR compatibility
- Pushes images to ECR repository
- Validates image availability

**Image Download Methods:**

*Method 1: Automatic Artifactory Download (Recommended)*
```bash
# Set your token
export HITACHI_ARTIFACTORY_TOKEN=your-token-here

# Run the script - it will automatically download and load the image
./02-prepare-images.sh dev
```

*Method 2: Manual Download and Load*
```bash
# Download manually from: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/
# Load the downloaded image
docker load -i pentaho-server-11.0.0.0-xxx.tar.gz

# Then run the script
./02-prepare-images.sh dev
```

**Expected time:** 5-10 minutes (depending on image size and download method)

**Verification:**
```bash
# Check ECR images
aws ecr describe-images --repository-name pentaho-server-dev --region us-west-2
```

### Step 3: Database Setup

```bash
./03-setup-database.sh dev
```

**What this does:**
- Waits for RDS instance to be available
- Creates JCR and Quartz databases
- Creates database users with appropriate permissions
- Executes schema creation scripts
- Creates Kubernetes secrets for database connectivity
- Validates database setup

**Expected time:** 2-5 minutes

**Verification:**
```bash
# Test database connectivity
kubectl get secrets -n pentaho-dev
psql -h <rds-endpoint> -U pentaho_jcr -d pentaho_jcr
```

### Step 4: Pentaho Deployment

```bash
./04-deploy-pentaho.sh dev
```

**What this does:**
- Configures kubectl for EKS cluster
- Generates Kubernetes manifests from templates
- Creates service accounts and RBAC
- Deploys Pentaho server with database connectivity
- Sets up LoadBalancer and Ingress
- Waits for deployment to be ready
- Validates deployment health

**Expected time:** 10-15 minutes

**Verification:**
```bash
# Check deployment status
kubectl get pods -n pentaho-dev
kubectl get services -n pentaho-dev

# Test Pentaho accessibility
curl -I http://<loadbalancer-endpoint>/pentaho/
```

### Step 5: Monitoring Setup

```bash
./05-monitoring-setup.sh dev
```

**What this does:**
- Sets up CloudWatch logging integration
- Installs Prometheus and Grafana via Helm
- Creates Pentaho-specific dashboards
- Configures automated backups
- Sets up health checks and alerting
- Creates management scripts

**Expected time:** 5-10 minutes

## Configuration

### Environment File Structure

The `pentaho-eks-{environment}.env` file contains all configuration settings:

```bash
# Environment Configuration
ENVIRONMENT=dev
PROJECT_NAME=pentaho-eks
AWS_REGION=us-west-2

# EKS Configuration
EKS_CLUSTER_NAME=pentaho-eks-dev
EKS_NODE_INSTANCE_TYPE=t3.large
EKS_NODE_MIN_SIZE=1
EKS_NODE_MAX_SIZE=5
EKS_NODE_DESIRED_SIZE=2

# Pentaho Configuration
PENTAHO_VERSION=11.0.0.0-28
PENTAHO_REPLICAS=1
PENTAHO_SERVER_NAME=pentaho-server-dev
PENTAHO_BASE_URL=https://pentaho-dev.yourcompany.com
PENTAHO_HOSTNAME=pentaho-dev.yourcompany.com

# Resource Limits
MEMORY_REQUEST=4Gi
MEMORY_LIMIT=8Gi
CPU_REQUEST=2000m
CPU_LIMIT=4000m
JAVA_OPTS="-Xms4g -Xmx6g -XX:+UseG1GC"

# Database Configuration
RDS_DB_INSTANCE_ID=pentaho-rds-dev
RDS_INSTANCE_CLASS=db.t3.medium
RDS_ALLOCATED_STORAGE=100
RDS_MASTER_USERNAME=postgres
RDS_MASTER_PASSWORD=your-secure-password

# JCR Database
JCR_DB_NAME=pentaho_jcr
JCR_DB_USER=pentaho_jcr
JCR_DB_PASSWORD=your-jcr-password

# Quartz Database
QUARTZ_DB_NAME=pentaho_quartz
QUARTZ_DB_USER=pentaho_quartz
QUARTZ_DB_PASSWORD=your-quartz-password

# Storage Configuration
S3_BUCKET_NAME=pentaho-eks-dev-storage-bucket
PERSISTENT_VOLUME_SIZE=100Gi

# Container Registry
ECR_REGION=us-west-2
ECR_ACCOUNT_ID=123456789012
ECR_REPOSITORY_NAME=pentaho-server-dev

# Networking
K8S_NAMESPACE=pentaho-dev
VPC_CIDR=10.0.0.0/16
```

### Customization Options

**Environment Sizes:**
- **Development:** `t3.medium` nodes, `db.t3.small` RDS, 50GB storage
- **Staging:** `t3.large` nodes, `db.t3.medium` RDS, 100GB storage  
- **Production:** `m5.xlarge` nodes, `db.r5.large` RDS, 500GB+ storage

**Scaling Configuration:**
```bash
# Horizontal scaling
PENTAHO_REPLICAS=3
EKS_NODE_DESIRED_SIZE=3

# Vertical scaling
MEMORY_REQUEST=8Gi
MEMORY_LIMIT=16Gi
CPU_REQUEST=4000m
CPU_LIMIT=8000m
```

## Monitoring and Management

### Access Monitoring Tools

**Grafana Dashboard:**
```bash
# Port forward to access locally
kubectl port-forward --namespace monitoring service/prometheus-grafana 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (get with: kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
```

**Prometheus Metrics:**
```bash
kubectl port-forward --namespace monitoring service/prometheus-kube-prometheus-prometheus 9090:9090
# Access at http://localhost:9090
```

**CloudWatch Logs:**
```bash
aws logs tail /aws/eks/pentaho-eks-dev/pentaho --follow
```

### Management Scripts

After monitoring setup, use these scripts for common operations:

```bash
# Scale deployment
./scripts/scale-pentaho.sh 3  # Scale to 3 replicas

# Restart deployment
./scripts/restart-pentaho.sh

# Get application logs
./scripts/get-logs.sh 100  # Last 100 lines

# Access pod shell
./scripts/shell-access.sh

# Manual backup
./scripts/backup-pentaho.sh

# Health check
./scripts/health-check.sh
```

### Backup and Restore

**Automated Backups:**
- Daily backups to S3 at 2 AM UTC
- Includes application data, database dumps, and configurations
- Configurable retention periods

**Manual Backup:**
```bash
./scripts/backup-pentaho.sh
```

**Restore Process:**
```bash
# List available backups
aws s3 ls s3://pentaho-eks-dev-storage-bucket/pentaho-backups/

# Download and restore
aws s3 cp s3://pentaho-eks-dev-storage-bucket/pentaho-backups/backup-20241201_020000.tar.gz .
# Extract and restore (detailed instructions in backup documentation)
```

## Troubleshooting

### Common Issues

**1. EKS Cluster Creation Fails**
```bash
# Check CloudFormation stack events
aws cloudformation describe-stack-events --stack-name eksctl-pentaho-eks-dev-cluster

# Check IAM permissions
aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names eks:CreateCluster
```

**2. Image Pull Errors**
```bash
# Check ECR authentication
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com

# Verify image exists
aws ecr describe-images --repository-name pentaho-server-dev --region us-west-2
```

**2a. Artifactory Download Issues**
```bash
# Verify token is set
echo $HITACHI_ARTIFACTORY_TOKEN

# Test token validity
curl -H "Authorization: Bearer ${HITACHI_ARTIFACTORY_TOKEN}" \
     https://one.hitachivantara.com/artifactory/api/system/ping

# Manual download with curl (if automatic fails)
curl -L -H "Authorization: Bearer ${HITACHI_ARTIFACTORY_TOKEN}" \
     -o pentaho-server-11.0.0.0-xxx.tar.gz \
     "https://one.hitachivantara.com/artifactory/pdc-generic-release/pentaho/pdc-docker-deployment/release-v11.0.0.0/pentaho-server-11.0.0.0-xxx.tar.gz"

# Load manually downloaded image
docker load -i pentaho-server-11.0.0.0-xxx.tar.gz
```

**3. Database Connection Issues**
```bash
# Test RDS connectivity
kubectl exec -n pentaho-dev deployment/pentaho-server -- psql -h <rds-endpoint> -U pentaho_jcr -d pentaho_jcr -c "SELECT version();"

# Check security groups
aws rds describe-db-instances --db-instance-identifier pentaho-rds-dev --query 'DBInstances[0].VpcSecurityGroups'
```

**4. Pod Startup Issues**
```bash
# Check pod status and events
kubectl describe pod -n pentaho-dev -l app=pentaho-server

# Check logs
kubectl logs -n pentaho-dev -l app=pentaho-server --tail=100

# Check resource limits
kubectl top pods -n pentaho-dev
```

**5. LoadBalancer Not Accessible**
```bash
# Check service status
kubectl get service -n pentaho-dev pentaho-server-service

# Check AWS Load Balancer Controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify security group rules
aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-elb-*"
```

### Debug Commands

```bash
# Get cluster information
kubectl cluster-info
kubectl get nodes -o wide

# Check all resources in namespace
kubectl get all -n pentaho-dev

# Describe problematic resources
kubectl describe deployment pentaho-server -n pentaho-dev
kubectl describe service pentaho-server-service -n pentaho-dev

# Get events
kubectl get events -n pentaho-dev --sort-by=.metadata.creationTimestamp

# Check resource usage
kubectl top nodes
kubectl top pods -n pentaho-dev
```

### Log Analysis

**Application Logs:**
```bash
# Follow live logs
kubectl logs -n pentaho-dev -l app=pentaho-server -f

# Search for errors
kubectl logs -n pentaho-dev -l app=pentaho-server | grep -i error

# Get logs from specific time
kubectl logs -n pentaho-dev deployment/pentaho-server --since=1h
```

**System Logs:**
```bash
# Check kube-system pods
kubectl get pods -n kube-system

# AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

## Cleanup

### Complete Environment Teardown

```bash
# Safe teardown with confirmation
./99-teardown.sh dev

# Force teardown (no confirmation)
./99-teardown.sh dev --force
```

**What gets deleted:**
- Kubernetes resources and namespace
- EKS cluster and node groups
- RDS database instance (with optional final snapshot)
- S3 storage bucket and contents
- ECR repository and images
- IAM roles and policies
- Security groups and VPC resources
- Local configuration files

**Verification after teardown:**
```bash
# Check no EKS clusters remain
aws eks list-clusters --region us-west-2

# Check no RDS instances remain
aws rds describe-db-instances --region us-west-2

# Check S3 buckets
aws s3api list-buckets --query 'Buckets[?contains(Name, `dev`)].Name'

# Check AWS costs
aws ce get-cost-and-usage --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics BlendedCost
```

### Partial Cleanup

To remove only specific components:

```bash
# Remove only monitoring
helm uninstall prometheus --namespace monitoring
kubectl delete namespace monitoring

# Remove only Pentaho deployment (keep infrastructure)
kubectl delete namespace pentaho-dev

# Remove only databases (keep cluster)
aws rds delete-db-instance --db-instance-identifier pentaho-rds-dev --skip-final-snapshot
```

## Next Steps

1. **Security Hardening:** Review and implement additional security measures
2. **Performance Tuning:** Optimize resource allocations based on usage patterns
3. **High Availability:** Configure multi-AZ deployment for production
4. **Disaster Recovery:** Implement cross-region backup and recovery procedures
5. **Integration:** Connect with existing authentication systems (LDAP, SAML, etc.)
6. **Custom Configurations:** Add custom Pentaho plugins and configurations
7. **Monitoring Enhancement:** Add custom dashboards and alert rules

For additional support and advanced configurations, refer to the main project documentation and Pentaho official documentation.
