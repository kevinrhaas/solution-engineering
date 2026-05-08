# 🚀 Glossary App - Quick Reference

## Current Deployments
- **Production**: `http://[prod-instance-ip]` 
- **Test**: `http://[test-instance-ip]`
- **Health**: `http://[instance-ip]/health`

## Common Commands
```bash
# Deploy new environment
./deploy/00-full-deploy.sh [environment]

# Quick redeploy existing
./deploy/00-deploy.sh [environment]  

# Check status
./deploy/90-status.sh

# SSH access
ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@[instance-ip]
```

## API Endpoints
```bash
# Health check
curl http://[instance-ip]/health

# Analyze database schema
curl -X POST http://[instance-ip]/analyze \
  -H "Content-Type: application/json" \
  -d "{}"

# Generate PDC export
curl -X POST http://[instance-ip]/generate \
  -H "Content-Type: application/json" \
  -d '{"data": {...}}'
```

## Environment Management
- **Create**: `./deploy/00-full-deploy.sh [name]`
- **Update**: `./deploy/00-deploy.sh [name]`
- **Status**: `./deploy/90-status.sh [name]`
- **Delete**: `./deploy/99-destroy.sh [name]`

## Network Access
- **Type**: Private VPC (requires VPN/internal network)
- **VPC**: `vpc-095f761a169c10b8e` (same as RDS)
- **Port**: 80 (all environments)
- **SSH Key**: `~/.ssh/pentaho+_se_keypair.pem`
