# Deployment Scripts Documentation

## 📁 Script Overview

### Core Deployment Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `00-full-deploy.sh` | **Complete deployment** - Creates instance + deploys app | `./00-full-deploy.sh [environment]` |
| `01-create-ec2-instance.sh` | Creates new EC2 instance for environment | `./01-create-ec2-instance.sh [environment]` |
| `02-transfer-and-build.sh` | Transfers files and builds Docker image | `./02-transfer-and-build.sh [environment]` |
| `03-deploy-app.sh` | Deploys application to existing instance | `./03-deploy-app.sh [environment]` |

### Management Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `00-deploy.sh` | **Quick redeploy** - Updates existing environment | `./00-deploy.sh [environment]` |
| `90-status.sh` | Check status of environments | `./90-status.sh [environment]` |
| `99-destroy.sh` | Terminate environment and cleanup | `./99-destroy.sh [environment]` |

## 🚀 Common Workflows

### New Environment Setup
```bash
# Create and deploy a new environment (e.g., dev)
./00-full-deploy.sh dev
```

### Daily Development Workflow
```bash
# Make code changes, then quick redeploy
./00-deploy.sh test

# Check if deployment succeeded
./90-status.sh test
```

### Production Deployment
```bash
# 1. Test in test environment first
./00-deploy.sh test
./90-status.sh test

# 2. If test passes, deploy to production
./00-deploy.sh prod
./90-status.sh prod
```

## 🌐 Network Access & Current Deployments

**All instances are in private VPC:**
- **Network**: Same VPC as RDS database (`vpc-095f761a169c10b8e`)
- **Access**: Requires VPN or internal network connectivity
- **SSH**: Uses `pentaho+_se_keypair.pem` key
- **Ports**: All applications run on port 80

**Get Current Deployment Info:**
```bash
# See all current deployments with IPs and status
./90-status.sh
```

### Environment Management Examples
```bash
# Standard environments
./99-destroy.sh prod
./99-destroy.sh test
./99-destroy.sh dev
./99-destroy.sh staging

# Custom environments
./99-destroy.sh feature-auth
./99-destroy.sh v2-beta
./99-destroy.sh hotfix-123

# Clean up everything
./99-cleanup.sh all
```
- **Security Group**: `sg-0eef78e9e17193950` (same as PDC servers)
- **Instance IP**: `10.80.230.59` (stable private IP)
- **Database Access**: Direct connectivity to `airlinesample.cyj079bqebpx.us-west-2.rds.amazonaws.com`

## Quick Start

### Initial Setup (One-time)
```bash
# 1. Create EC2 instance in RDS VPC
./01-create-ec2-instance.sh prod

# 2. Transfer files and build Docker image
./02-transfer-and-build.sh prod

# 3. Deploy the application
./03-deploy-app.sh prod prod
```

### Application Access
```bash
# SSH access (requires VPN or network connectivity)
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@10.80.230.59

# Application URLs (internal network)
Production: http://10.80.230.59
Test: http://10.80.230.59:8080
Health Check: http://10.80.230.59/health
```

## Deployment Scripts

### Core Deployment
- **`01-create-ec2-instance.sh`** - Creates EC2 instance in RDS VPC
- **`02-transfer-and-build.sh`** - Transfers code and builds Docker image
- **`03-deploy-app.sh`** - Deploys application (prod or test environment)

### Management
- **`90-status.sh`** - Check instance and application status
- **`99-cleanup.sh`** - Clean up resources when done

### Optional
- **`02-allocate-elastic-ip.sh`** - Not applicable (private VPC)
- **`README-local-build.md`** - Local development instructions

## Daily Development Workflow

### Code Updates
```bash
# 1. Update application code locally
# 2. Transfer and rebuild
./02-transfer-and-build.sh prod

# 3. Deploy production
./03-deploy-app.sh prod prod

# 4. Deploy test (optional)
./03-deploy-app.sh prod test
```

### Environment Management
```bash
# Check status
./90-status.sh prod

# SSH for debugging
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@10.80.230.59

# View logs
docker logs glossary-app           # Production
docker logs glossary-app-test      # Test

# Restart services
docker restart glossary-app        # Production
docker restart glossary-app-test   # Test
```

## Configuration

### Environment Variables
The application uses the standard `.env` file for configuration:
- Database connection to Neon PostgreSQL (default)
- API endpoints for OpenAI services
- All standard application settings

### Database Testing
To test with different databases (like airlinesample), update the `.env` file on the instance:
```bash
# SSH to instance
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@10.80.230.59

# Update database configuration
cd /home/ec2-user/app
cp .env .env.backup
# Edit .env with new DATABASE_URL and DATABASE_SCHEMA

# Restart application
docker restart glossary-app
```

## Network Requirements

### VPN/Network Access
This deployment requires VPN or internal network access to:
- SSH to the instance (10.80.230.59)
- Access the web application
- Perform management tasks

### Security Groups
The instance uses the same security group as PDC servers (`sg-0eef78e9e17193950`) which provides:
- SSH access (port 22)
- HTTP access (port 80)
- Custom ports (8080)
- Database connectivity to RDS

## Cost and Scaling

### Monthly Costs (~$15)
- EC2 t3.small instance: ~$15/month
- EBS storage (8GB): ~$1/month
- No additional load balancer or NAT gateway costs

### Scaling Options
- **Vertical**: Increase instance size (t3.medium, t3.large)
- **Horizontal**: Create additional instances in different AZs
- **Load Balancing**: Add ALB for production workloads

## Troubleshooting

### Common Issues
```bash
# Check instance status
./90-status.sh prod

# SSH connection issues
# Verify VPN connection and network access to 10.80.230.59

# Application not responding
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@10.80.230.59
docker ps                    # Check container status
docker logs glossary-app     # View application logs
```

### Database Connectivity
```bash
# Test database connection from instance
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@10.80.230.59
timeout 10 bash -c '</dev/tcp/airlinesample.cyj079bqebpx.us-west-2.rds.amazonaws.com/5432'
echo $?  # 0 = success, 1 = failed
```

## Archive

Previous deployment configurations (ECS, App Runner, etc.) have been moved to the `archive/` directory for reference.
