# Solution Engineering Repository

⚠️ **EXPERIMENTAL PROJECT** ⚠️
> This repository contains experimental automation tools and deployment systems that are actively being developed and tested. Use at your own risk and expect breaking changes.

This repository contains solution engineering resources and projects for Pentaho.

## Projects

### 🐳 [Pentaho Docker Deploy](./pentaho-docker-deploy/)
Automated deployment system for Pentaho Business Analytics & Data Integration Server using Docker containers on AWS EC2.

**Features:**
- Complete AWS EC2 provisioning automation
- Docker containerization using Pentaho's official DockMaker
- Flexible environment management (dev/test/prod/qa/etc.)
- SSH tunnel support and intelligent resource optimization
- Non-interactive deployment with comprehensive logging

### ⚓ [Pentaho AWS EKS Deploy](./pentaho-aws-eks-deploy/) 🧪 **EXPERIMENTAL**
Kubernetes-based deployment system for Pentaho Business Analytics Server 11.0.0.0 on AWS EKS with RDS PostgreSQL backend.

> ⚠️ **WARNING: EXPERIMENTAL PROJECT** - This project is under active development and requires specific AWS permissions and infrastructure setup. Not recommended for production use.

**Features:**
- AWS EKS cluster provisioning and management
- Pre-built Pentaho Docker images from Hitachi Vantara registry
- AWS RDS PostgreSQL backend with automated schema setup
- S3 integration for persistent storage and configuration overrides
- Kubernetes-native scaling and management
- Enterprise-grade monitoring and logging

### 📚 [Glossary](./glossary/)
AI-powered glossary generation and management application.

**Features:**
- Intelligent term extraction and definition generation
- REST API for integration with other systems
- Configurable AI models and processing pipelines
- Export capabilities for various formats

### 🎤 [TTS (Text-to-Speech)](./tts/)
Command-line tool for converting text files to high-quality speech using OpenAI's Text-to-Speech API.

**Features:**
- Convert any text file to high-quality speech audio
- Flexible input/output directory management with numbered files
- Configurable voice settings and AI model selection
- Line-by-line processing for presentations and structured content
- Secure API key management and environment configuration
- Simple command-line interface for batch processing

## Getting Started

Each project has its own README with detailed setup and usage instructions:

- **Pentaho Docker Deploy:** See [pentaho-docker-deploy/README.md](./pentaho-docker-deploy/README.md)
- **Pentaho AWS EKS Deploy:** See [pentaho-aws-eks-deploy/README.md](./pentaho-aws-eks-deploy/README.md)
- **Glossary:** See [glossary/README.md](./glossary/README.md)

## Repository Structure

```
solution-engineering/
├── README.md                          # This file
├── pentaho-docker-deploy/             # Docker deployment automation (EC2-based)
│   ├── 01-create-pentaho-ec2.sh
│   ├── 02-download-pentaho-files.sh
│   ├── 03-build-pentaho-containers.sh
│   ├── 04-deploy-pentaho.sh
│   ├── full-deployment.sh
│   └── README.md
├── pentaho-aws-eks-deploy/            # Kubernetes deployment automation (EKS-based)
│   ├── 01-setup-infrastructure.sh
│   ├── 02-prepare-images.sh
│   ├── 03-setup-database.sh
│   ├── 04-deploy-pentaho.sh
│   ├── full-deployment.sh
│   ├── kubernetes/                    # Kubernetes manifests
│   └── README.md
└── glossary/                          # AI-powered glossary application  
    ├── app.py
    ├── requirements.txt
    └── README.md
```

---

*Repository initialized on August 25, 2025*
