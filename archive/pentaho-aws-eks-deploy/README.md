# Pentaho AWS EKS Deployment 🧪

> ## ⚠️ **EXPERIMENTAL PROJECT - USE AT YOUR OWN RISK** ⚠️
> 
> **This project is currently under active development and testing.**
> 
> - 🚧 **NOT READY FOR PRODUCTION USE**
> - ⚠️ **Requires specific AWS permissions and infrastructure setup**  
> - 🔧 **Breaking changes expected as development continues**
> - 🐛 **May contain bugs or incomplete functionality**
> - 📝 **Documentation may be incomplete or outdated**
> 
> **Use this project only for:**
> - ✅ Development and testing environments
> - ✅ Learning and experimentation
> - ✅ Contributing to the project development
>
> **Before proceeding, ensure you understand the risks and have appropriate AWS permissions.**

---

Kubernetes-based deployment system for Pentaho Business Analytics Server 11.0.0.0 on AWS EKS with RDS PostgreSQL backend.

## Overview

This project automates the deployment of Pentaho Server using:
- **AWS EKS (Elastic Kubernetes Service)** for container orchestration
- **AWS RDS PostgreSQL** for database backend  
- **AWS ECR (Elastic Container Registry)** for Docker image storage
- **AWS S3** for persistent storage and configuration overrides
- **Pre-built Pentaho Docker images** from Hitachi Vantara registry
- **Kubernetes manifests** for declarative deployment

## Quick Start

> ⚠️ **EXPERIMENTAL FEATURE** - This quick start assumes you have the necessary AWS permissions and understand the risks. Proceed with caution.

For experienced users who want to deploy immediately:

```bash
# 1. Clone and configure
git clone <repository-url>
cd pentaho-aws-eks-deploy
cp pentaho-eks-sample.env pentaho-eks-dev.env
# Edit pentaho-eks-dev.env with your settings

# 2. Complete deployment (20-30 minutes)
./01-setup-infrastructure.sh dev
./02-prepare-images.sh dev
./03-setup-database.sh dev
./04-deploy-pentaho.sh dev
./05-monitoring-setup.sh dev

# 3. Access Pentaho
kubectl get service -n pentaho-dev
# Use LoadBalancer endpoint: http://<external-ip>/pentaho/
```

📖 **For detailed instructions, troubleshooting, and customization options, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)**

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      EKS Cluster                            ││
│  │                                                             ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │              Pentaho Server Pod                         │││
│  │  │  ┌─────────────────────────────────────────────────────┐│││
│  │  │  │    Pentaho Server 11.0.0.0 Container               ││││
│  │  │  │    - Tomcat Web Server                              ││││
│  │  │  │    - Business Analytics Engine                      ││││
│  │  │  │    - PDI (Carte, Kitchen, Pan)                     ││││
│  │  │  └─────────────────────────────────────────────────────┘│││
│  │  │                                                         │││
│  │  │  Persistent Volume → S3 Bucket                          │││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   RDS PostgreSQL                            ││
│  │  - hibernate (Pentaho Repository)                           ││
│  │  - quartz (Scheduling)                                      ││
│  │  - jackrabbit (Content Repository)                          ││
│  │  - pentaho_logging                                          ││
│  │  - pentaho_mart                                             ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    S3 Bucket                                ││
│  │  - Software overrides                                       ││
│  │  - Configuration files                                      ││
│  │  - Persistent data storage                                  ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    ECR Registry                              ││
│  │  - pentaho-server:11.0.0.0-xxx                             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Key Differences from Docker-EC2 Approach

| Aspect | Docker-EC2 (Current) | EKS-Kubernetes (New) |
|--------|---------------------|----------------------|
| **Orchestration** | Docker Compose on single EC2 | Kubernetes on EKS cluster |
| **Image Source** | Built with DockMaker tool | Pre-built from HV registry |
| **Database** | Containerized PostgreSQL | AWS RDS PostgreSQL |
| **Storage** | EBS volumes | S3 buckets + Persistent volumes |
| **Scaling** | Manual vertical scaling | Kubernetes horizontal/vertical scaling |
| **Persistence** | Container volumes | Kubernetes Persistent Volume Claims |
| **Version** | Pentaho 10.2.0.0 | Pentaho 11.0.0.0 |

## Prerequisites

### Required Software
- **AWS CLI** with configured credentials
- **kubectl** for Kubernetes cluster management
- **Docker** for image operations
- **Okta-AWS CLI** for HV AD users
- **JFrog CLI** for accessing HV Docker registry

### Required Permissions
- **EKS cluster creation and management**
- **RDS instance creation and management**  
- **ECR repository access**
- **S3 bucket creation and management**
- **IAM role and policy management**

### Authentication Setup
```bash
# AWS authentication via Okta
okta-aws ${yourprofile} sts get-caller-identity

# ECR authentication (automated by scripts)
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 524647911006.dkr.ecr.us-east-2.amazonaws.com

# Hitachi Vantara Artifactory token (for automatic image download)
export HITACHI_ARTIFACTORY_TOKEN=your-token-here
# Generate token at: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/
```

## Quick Start

1. **Configure environment:**
   ```bash
   cp pentaho-eks-sample.env pentaho-eks-dev.env
   # Edit pentaho-eks-dev.env with your settings
   ```

2. **Download Pentaho images:**
   ```bash
   # Download from: https://one.hitachivantara.com/ui/native/pntprv-generic-dev/pentaho/pdia-image-configurator/
   docker load -i pentaho-server-11.0.0.0-xxx.tar.gz
   ```

3. **Run full deployment:**
   ```bash
   ./01-setup-infrastructure.sh dev     # Create EKS, RDS, S3, ECR
   ./02-prepare-images.sh dev           # Tag and push Docker images  
   ./03-setup-database.sh dev           # Initialize PostgreSQL schemas
   ./04-deploy-pentaho.sh dev           # Deploy to Kubernetes
   ```

4. **Access Pentaho:**
   ```bash
   kubectl port-forward svc/pentaho-server 8080:8080 -n pentaho-server
   # Open: http://localhost:8080/pentaho
   ```

## Project Structure

```
pentaho-aws-eks-deploy/
├── README.md                           # This file
├── DEPLOYMENT-GUIDE.md                 # Comprehensive deployment guide
├── pentaho-eks-sample.env              # Sample configuration file
├── 01-setup-infrastructure.sh          # EKS cluster and infrastructure setup
├── 02-prepare-images.sh                # Docker image preparation and ECR push
├── 03-setup-database.sh                # Database initialization and configuration
├── 04-deploy-pentaho.sh                # Kubernetes deployment and services
├── 05-monitoring-setup.sh              # Monitoring, backup, and management setup
├── 99-teardown.sh                      # Complete environment cleanup
├── database/
│   ├── create_jcr_postgresql.sql      # JCR (Jackrabbit) database schema
│   └── create_quartz_postgresql.sql   # Quartz scheduler database schema
├── kubernetes/
│   ├── namespace.yaml                  # Kubernetes namespace configuration
│   └── persistent-volume.yaml         # Persistent storage configuration
├── monitoring/                         # Generated monitoring configurations
├── scripts/                           # Generated management scripts
└── .gitignore                         # Git ignore rules
```

## Features

### ✅ Complete Infrastructure Automation
- **EKS cluster** provisioning with managed node groups
- **RDS PostgreSQL** setup with high availability options
- **S3 bucket** creation for persistent storage and backups
- **ECR repository** management for container images
- **VPC and networking** configuration with security groups
- **IAM roles and policies** with least-privilege access

### ✅ Database Management
- **Automated database creation** (JCR, Quartz) with proper schemas
- **User management** with secure password handling
- **Database connectivity validation** and health checks
- **Backup automation** with configurable retention
- **Schema migration** support for version upgrades

### ✅ Container Operations
- **Multi-source image support** (Hitachi Vantara Artifactory, local, registry, ECR)
- **Automated Artifactory download** with token authentication
- **Automated ECR authentication** and image pushing
- **Image validation** and integrity checks
- **Version management** with tagging strategies
- **Container security scanning** integration

### ✅ Kubernetes Deployment
- **Declarative manifests** with environment templating
- **Resource management** with requests and limits
- **Health checks** and probes configuration
- **Service discovery** and load balancing
- **Persistent storage** with dynamic provisioning
- **RBAC** and security context configuration

### ✅ Enterprise Monitoring
- **Prometheus metrics** collection and alerting
- **Grafana dashboards** with Pentaho-specific visualizations
- **CloudWatch integration** for logs and metrics
- **Health checks** and automated remediation
- **Performance monitoring** and resource optimization
- **Alerting** via multiple channels (email, Slack, SNS)

### ✅ Operations and Management
- **Automated backups** to S3 with encryption
- **Scaling operations** (horizontal and vertical)
- **Rolling updates** with zero downtime
- **Configuration management** via ConfigMaps and Secrets
- **Log aggregation** and analysis
- **Troubleshooting tools** and debug utilities

## Deployment Workflow

The deployment follows a sequential process across 5 main phases:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Infrastructure │ → │     Images      │ → │    Database     │
│                 │    │                 │    │                 │
│ • EKS Cluster   │    │ • Pull/Load     │    │ • RDS Setup     │
│ • RDS Instance  │    │ • Tag & Push    │    │ • Schema Init   │
│ • S3 Bucket     │    │ • ECR Registry  │    │ • User Creation │
│ • ECR Repo      │    │ • Validation    │    │ • Connectivity  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ↓                       ↓                       ↓
┌─────────────────┐    ┌─────────────────┐
│   Deployment    │ → │    Monitoring   │
│                 │    │                 │
│ • Kubernetes    │    │ • Prometheus    │
│ • Services      │    │ • Grafana       │
│ • Ingress       │    │ • CloudWatch    │
│ • Validation    │    │ • Backup Jobs   │
└─────────────────┘    └─────────────────┘
```

**Phase 1: Infrastructure (15-20 min)**
- Creates all AWS resources (EKS, RDS, S3, ECR)
- Configures networking and security
- Sets up IAM roles and policies

**Phase 2: Images (5-10 min)**
- Handles Docker image preparation
- Authenticates and pushes to ECR
- Validates image availability

**Phase 3: Database (2-5 min)**
- Initializes PostgreSQL schemas
- Creates users and permissions
- Validates connectivity

**Phase 4: Deployment (10-15 min)**
- Deploys Pentaho to Kubernetes
- Configures services and ingress
- Waits for readiness

**Phase 5: Monitoring (5-10 min)**
- Sets up comprehensive monitoring
- Configures automated backups
- Creates management tools
- **ECR repository** setup for Docker images
- **IAM roles and policies** configuration

### ✅ Image Management
- **Pre-built image** download and verification
- **Automated tagging** for ECR compatibility
- **ECR push** with proper authentication
- **Multi-architecture** support (AMD64/ARM64)

### ✅ Database Management  
- **Automated schema** creation for all Pentaho databases
- **Connection validation** and testing
- **Backup and restore** utilities
- **Migration support** from other database types

### ✅ Kubernetes Deployment
- **Declarative manifests** for consistent deployment
- **Persistent volume claims** for S3 integration
- **Service accounts** with proper RBAC
- **Resource limits** and requests optimization
- **Health checks** and readiness probes

### ✅ Monitoring and Management
- **Centralized logging** with CloudWatch integration
- **Metrics collection** for performance monitoring
- **Automated scaling** based on resource utilization
- **Rolling updates** with zero-downtime deployment

## Getting Started

Ready to deploy? See [QUICK-START.md](./docs/QUICK-START.md) for detailed setup instructions.

For architecture details, see [ARCHITECTURE.md](./docs/ARCHITECTURE.md).

For troubleshooting, see [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md).

---

*Built for Pentaho 11.0.0.0 on AWS EKS • Solution Engineering Team • 2025*
