# Aperture

AI-powered lead generation and adjudication system using Pentaho Data Integration (PDI) with Azure OpenAI and Google Gemini.

> **⚠️ Development Status:** This project is a proof-of-concept and not production-ready. Use for reference and experimentation only.

## Overview

Aperture automates lead generation and quality scoring through multi-stage AI pipelines, integrating with enterprise analytics via Pentaho Analyzer OLAP cubes.

**Core Capabilities:**
- AI-driven lead generation from account owner data
- Multi-model adjudication (Azure OpenAI, Google Gemini)
- Quality scoring and categorization (High/Medium/Low)
- OLAP analytics with Mondrian schema
- Batch processing with error handling and retry logic

## Architecture

### Data Flow
```
Account Data → Generate Leads (Azure/Gemini) → Adjudicate Quality (Gemini) → Score & Load → Analytics
```

### Components

#### `/main` - Production ETL Jobs
- **`main-call-generate-leads-azure-openai.kjb`** - Generate leads using Azure OpenAI
- **`main-call-adjudicate-gemini.kjb`** - Adjudicate lead quality with Google Gemini
- **`generate-raw-lead-azure.ktr`** - Core lead generation transformation
- **`adjudicate-lead-gemini.ktr`** - Lead quality adjudication transformation
- **`load-adj-lead-score.ktr`** - Load scored leads to database
- **`assign-run-id.ktr`** - Track batch execution
- **`increment-count.ktr`** - Manage batch counters

#### `/analyzer` - OLAP Analytics
- **`lead_generation.xml`** - Mondrian schema for "Adjudicated Lead Generation" cube
  - **Dimensions**: Lead Quality Category, Target Score Range (0-100 in 5-point buckets), Geography (Region/Subregion), Account Owner, Contact details, Organization
  - **Measures**: Lead Count, Target Score, Confidence Scores (Org/Contact/Email/Phone), Process/Execution Time
  - **Calculated Measures**: High/Medium/Low Quality Leads, Average Overall Confidence Score

#### `/data` - Sample Data
- `202512011653_raw_lead_generation.csv` - Raw AI-generated leads
- `202512161545_vw_adj_lead_generation_main.csv` - Adjudicated lead scores

#### `/examples` - Reference Implementations
- **`azure/`** - Azure Cognitive Search & Functions integration
- **`gemini/`** - Google Vertex AI, Gemini, Document AI, BigQuery
- **`bedrock/`** - AWS Bedrock model invocations
- **`openai/`** - Direct OpenAI API calls

## Database Schema

**Core Tables:**

| Table | Purpose |
|-------|---------|
| `account_owner` | Account owner master data with geography (region/subregion) |
| `prompt_library` | AI prompt templates and configurations |
| `raw_lead_generation` | AI-generated leads from Azure OpenAI with confidence scores |
| `adj_lead_generation` | Gemini adjudication results with rationale and verification URLs |
| `adj_lead_score` | Aggregated lead scores based on adjudication consensus |
| `run_log` | Batch execution tracking |

**Error Tables:**
- `err_lead_adjudication` - API call failures
- `err_lead_adjudication_api` - API-specific errors
- `err_lead_adjudication_unparsed` - Response parsing failures
- `log_exception` - General exception logging
- `log_lead_gen_req_resp` - Request/response logging

**Key View:**
- `vw_adj_lead_generation_main` - Joins scored leads (`adj_lead_score`) with raw lead data, adjudication rationale, and account owner geography

**Fuzzy Matching:**
Three automatic fuzzy match keys generated via triggers:
- `fuzzy_match_key` - Org + Location + Contact + Role + Email + Phone
- `fuzzy_match_contact_key` - Org + Location + Contact + Role
- `fuzzy_match_org_site_contact_key` - Org + Location + Contact

## Configuration

**Database:** PostgreSQL 13+ (`gen_ai` schema)

**AI Models:**
- Azure OpenAI: Lead generation from account owner context
- Google Gemini (Vertex AI): Lead quality adjudication and scoring

## Lead Quality Scoring

| Category | Score Range | Target Score Ranges |
|----------|-------------|---------------------|
| **High** | ≥ 70 | 70-74, 75-79, 80-84, 85-89, 90-94, 95-100 |
| **Medium** | 40-69 | 40-44, 45-49, 50-54, 55-59, 60-64, 65-69 |
| **Low** | < 40 | 00-04, 05-09, 10-14, 15-19, 20-24, 25-29, 30-34, 35-39 |

## Usage

### Generate Leads
```bash
# Run Azure OpenAI lead generation
kitchen.sh -file=main/main-call-generate-leads-azure-openai.kjb
```

### Adjudicate Quality
```bash
# Run Gemini adjudication
kitchen.sh -file=main/main-call-adjudicate-gemini.kjb
```

### Deploy Analytics Cube
1. Copy `analyzer/lead_generation.xml` to Pentaho Server schema directory
2. Refresh Pentaho Analyzer metadata
3. Create reports using "Adjudicated Lead Generation" cube

## Features

- **Batch Processing**: Configurable batch sizes with run ID tracking
- **Error Handling**: Automatic retry logic for API failures
- **Geography Hierarchy**: Drill-down analysis by Region → Subregion
- **Quality Segmentation**: Filter/analyze by High/Medium/Low categories
- **Score Distribution**: 20 granular score range buckets for detailed analysis
- **Confidence Metrics**: Separate scoring for organization, contact, email, phone validation

## Requirements

- Pentaho Data Integration 9.x+
- PostgreSQL 14+
- Azure OpenAI account
- Google Cloud Platform (Vertex AI enabled)
- Pentaho Server 9.x+ (for analytics)

## License

Proprietary - Solution Engineering
