# Pentaho Google Cloud Platform Integration Examples

## Overview

This demonstration pack showcases Pentaho Data Integration's capabilities for integrating with Google Cloud Platform services, including Gemini AI, BigQuery, Document AI, and Vertex AI embeddings. These examples demonstrate how to build modern data pipelines that combine traditional ETL with cutting-edge AI capabilities.

## Components

### Transformations (.ktr)

#### 1. `generate-response-gemini.ktr`
**Purpose:** Generate AI responses using Google's Gemini language model

**Capabilities:**
- Connects to Gemini API for text generation
- Supports multiple Gemini model versions (gemini-3-pro-preview, gemini-2.5-flash)
- Configurable context, domain, and industry parameters
- Ideal for content generation, analysis, and AI-powered data enrichment

**Parameters:**
- `CONTEXT`: Context for AI generation (default: "google technology partnerships")
- `DOMAIN`: Business domain (default: "Retail Banking")
- `INDUSTRY`: Industry vertical (default: "Financial Services")
- `MODEL`: Primary Gemini model version
- `TOKEN`: Google API authentication token

**Use Cases:**
- Generate industry-specific content
- Enrich data with AI-generated insights
- Create personalized responses based on data context
- Automate content creation workflows

---

#### 2. `generate-response-gemini-websearch.ktr`
**Purpose:** Generate AI responses using Gemini with web search capabilities

**Capabilities:**
- Enhanced Gemini integration with real-time web search
- Retrieves up-to-date information from the internet
- Same parametrization as standard Gemini transformation
- Combines AI reasoning with current web data

**Parameters:**
- Same as `generate-response-gemini.ktr`
- Includes web search grounding for more accurate, current responses

**Use Cases:**
- Generate responses requiring current events or facts
- Market research and competitive analysis
- Real-time data enrichment
- Fact-checking and verification workflows

---

#### 3. `generate-embedding-vertex.ktr`
**Purpose:** Generate vector embeddings using Google Vertex AI

**Capabilities:**
- Creates text embeddings for semantic search and similarity matching
- Integrates with Vertex AI's text-embedding-gecko model
- Configurable dimensionality (default: 768 dimensions)
- Supports batch processing of multiple text items

**Parameters:**
- `CONTEXT`: Context for embedding generation
- `DOMAIN`: Business domain
- `INDUSTRY`: Industry context
- `NUM_TABLES`: Number of tables/items to process
- `OUTFILE`: Output file path
- `TOKEN`: Google API authentication token

**Use Cases:**
- Build semantic search systems
- Create product recommendation engines
- Document similarity analysis
- Knowledge base indexing
- Vector database population

---

#### 4. `process-document-documentai.ktr`
**Purpose:** Process documents using Google Document AI

**Capabilities:**
- Automated document parsing and extraction
- OCR and intelligent document understanding
- Structured data extraction from unstructured documents
- Supports various document types (invoices, forms, receipts, etc.)

**Parameters:**
- `CONTEXT`: Processing context
- `DOMAIN`: Document domain
- `INDUSTRY`: Industry classification
- `NUM_TABLES`: Number of tables to process
- `OUTFILE`: Output destination
- `TOKEN`: Google API authentication token

**Use Cases:**
- Invoice processing and data extraction
- Form digitization
- Receipt parsing
- Contract analysis
- Document classification and routing

---

#### 5. `biqquery-jdbc-connect-test.ktr`
**Purpose:** Test JDBC connectivity to Google BigQuery

**Capabilities:**
- Validates BigQuery connection configuration
- Tests authentication and authorization
- Verifies network connectivity
- Provides connection diagnostics

**Use Cases:**
- Connection troubleshooting
- Environment validation
- Pre-deployment testing
- Configuration verification

---

#### 6. `command-test.ktr`
**Purpose:** Test command-line integration and API calls

**Capabilities:**
- Simple command execution testing
- API endpoint validation
- Parameter passing demonstration
- Basic Gemini API interaction test

**Parameters:**
- `PROMPT`: Test prompt (default: "Give me your funniest joke in the form Q: Joke A: Answer")

**Use Cases:**
- Integration testing
- API troubleshooting
- Quick validation of AI responses
- Development and debugging

---

#### 7. `increment-count.ktr`
**Purpose:** Utility transformation for retry logic and counting operations

**Capabilities:**
- Implements retry counter logic
- Supports iterative processing
- Error handling with retry mechanisms

**Parameters:**
- `RETRY_COUNT`: Current retry count

**Use Cases:**
- API retry logic
- Batch processing with error recovery
- Rate limiting handling
- Workflow control flow

---

### Jobs (.kjb)

#### 1. `bigquery-loader.kjb`
**Purpose:** Orchestrate data loading into Google BigQuery

**Capabilities:**
- Coordinates multi-step data loading process
- Handles data validation and transformation
- Manages error handling and logging
- Supports incremental and full loads

**Use Cases:**
- ETL pipeline orchestration
- Data warehouse loading
- Scheduled data integration
- Multi-source data consolidation

---

### Reference Files

#### 1. `gemini-model-commands`
**Purpose:** Reference file containing curl commands for Gemini and Vertex AI API calls

**Contents:**
- Vertex AI embedding API example
- OAuth2 device code flow
- Authentication examples
- API endpoint references

**Use Cases:**
- API reference and documentation
- Manual testing and debugging
- Integration development
- Authentication troubleshooting

---

#### 2. `gemini-vector-store-cross-product-analysis`
**Purpose:** SQL query examples for vector similarity search

**Contents:**
- PostgreSQL vector similarity queries
- Cosine similarity calculations
- Product recommendation query patterns
- Vector database operations

**Use Cases:**
- Implementing semantic search
- Building recommendation systems
- Vector similarity analysis
- Database query optimization

---

## Prerequisites

### Google Cloud Platform Setup
1. **Google Cloud Project**: Active GCP project with billing enabled
2. **APIs Enabled**:
   - Vertex AI API
   - Cloud Document AI API
   - BigQuery API
   - Gemini API
3. **Authentication**:
   - API key or OAuth2 credentials
   - Service account with appropriate permissions
   - IAM roles: AI Platform User, BigQuery Data Editor, Document AI Editor

### Pentaho Setup
1. **Pentaho Data Integration 9.x or higher**
2. **Required Plugins**:
   - REST Client step
   - JSON Input/Output steps
   - BigQuery connector (if using JDBC)
3. **Java 8 or higher**
4. **Network connectivity to GCP services**

### Dependencies
- **Google Cloud SDK** (optional, for gcloud commands)
- **BigQuery JDBC Driver** (for BigQuery connectivity)
- **JSON libraries** (included with Pentaho)

---

## Configuration

### Setting Up Authentication

1. **API Key Method** (Simplest):
   ```bash
   # Create API key in Google Cloud Console
   # Navigate to: APIs & Services > Credentials > Create Credentials > API Key
   # Copy the key and use in TOKEN parameters
   ```

2. **Service Account Method** (Recommended for production):
   ```bash
   # Create service account
   gcloud iam service-accounts create pentaho-integration \
     --display-name="Pentaho Integration Service Account"
   
   # Grant necessary roles
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:pentaho-integration@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   
   # Download JSON key
   gcloud iam service-accounts keys create pentaho-key.json \
     --iam-account=pentaho-integration@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```

### Parameter Configuration

Update the following parameters in each transformation according to your environment:

```properties
# Authentication
TOKEN=your-api-key-here

# Project Configuration
CONTEXT=your-business-context
DOMAIN=your-domain
INDUSTRY=your-industry

# Model Selection
MODEL=gemini-3-pro-preview  # or gemini-2.5-flash for faster responses

# BigQuery Configuration
PROJECT_ID=your-gcp-project-id
DATASET=your-dataset-name
TABLE=your-table-name
```

---

## Quick Start Guide

### Example 1: Generate AI Content

1. Open `generate-response-gemini.ktr` in Pentaho Spoon
2. Update the `TOKEN` parameter with your API key
3. Modify `CONTEXT`, `DOMAIN`, and `INDUSTRY` as needed
4. Run the transformation
5. Review the generated content in the output

### Example 2: Create Text Embeddings

1. Open `generate-embedding-vertex.ktr`
2. Configure authentication token
3. Set `NUM_TABLES` to number of items to process
4. Specify `OUTFILE` for output location
5. Run transformation to generate embeddings
6. Use output with vector database or similarity search

### Example 3: Process Documents

1. Open `process-document-documentai.ktr`
2. Configure Document AI processor details
3. Set input document source
4. Run transformation
5. Extract structured data from output

### Example 4: Load Data to BigQuery

1. Open `bigquery-loader.kjb`
2. Configure BigQuery connection details
3. Set source data parameters
4. Run job to load data
5. Verify data in BigQuery console

---

## Architecture Patterns

### Pattern 1: AI-Enhanced ETL Pipeline
```
Data Source → Extract → Gemini AI Enrichment → Transform → BigQuery Load
```
Use `generate-response-gemini.ktr` to enrich extracted data before loading.

### Pattern 2: Semantic Search System
```
Documents → Document AI → Text Extraction → Vertex Embeddings → Vector DB → Search API
```
Combine `process-document-documentai.ktr` and `generate-embedding-vertex.ktr`.

### Pattern 3: Intelligent Document Processing
```
Document Upload → Document AI Processing → Data Extraction → Validation → BigQuery
```
Use `process-document-documentai.ktr` with `bigquery-loader.kjb`.

### Pattern 4: Real-Time Content Generation
```
Trigger Event → Context Retrieval → Gemini with Web Search → Content Output
```
Use `generate-response-gemini-websearch.ktr` for current information.

---

## Best Practices

### Performance Optimization
1. **Batch Processing**: Process embeddings and AI requests in batches to reduce API calls
2. **Rate Limiting**: Implement retry logic using `increment-count.ktr`
3. **Caching**: Cache frequently requested embeddings and responses
4. **Parallel Processing**: Use Pentaho's parallel execution for independent operations

### Security
1. **Never commit API keys**: Use Pentaho parameters or environment variables
2. **Use service accounts**: Prefer service account authentication for production
3. **Minimal permissions**: Grant only necessary IAM roles
4. **Audit logging**: Enable Cloud Audit Logs for compliance

### Error Handling
1. **Implement retries**: Use exponential backoff for API failures
2. **Log errors**: Capture detailed error messages for troubleshooting
3. **Validate inputs**: Check data quality before API calls
4. **Monitor quotas**: Track API usage against project quotas

### Cost Management
1. **Choose appropriate models**: Use flash models for simple tasks
2. **Optimize embeddings**: Set appropriate dimensionality
3. **Monitor usage**: Track API calls and costs in GCP console
4. **Implement caching**: Reduce redundant API calls

---

## Troubleshooting

### Common Issues

#### Authentication Errors
```
Error: 401 Unauthorized
Solution: Verify API key is valid and has necessary permissions
Check: Cloud Console > APIs & Services > Credentials
```

#### Rate Limiting
```
Error: 429 Too Many Requests
Solution: Implement retry logic with increment-count.ktr
Add: Exponential backoff between retries
```

#### Connection Timeouts
```
Error: Connection timeout to API endpoint
Solution: Check network connectivity and firewall rules
Verify: GCP API endpoints are accessible from your network
```

#### BigQuery JDBC Connection
```
Error: Cannot connect to BigQuery
Solution: Verify JDBC driver is installed and connection string is correct
Check: Authentication credentials and project permissions
```

---

## Sample Use Cases

### Financial Services
- **Invoice Processing**: Extract data from invoices using Document AI
- **Fraud Detection**: Use embeddings for transaction similarity analysis
- **Customer Service**: Generate personalized responses with Gemini
- **Report Generation**: Automate financial reports with AI assistance

### Retail
- **Product Recommendations**: Build semantic search with embeddings
- **Inventory Analysis**: AI-powered insights using Gemini
- **Customer Analytics**: Load and analyze data in BigQuery
- **Content Creation**: Generate product descriptions and marketing copy

### Healthcare
- **Medical Record Processing**: Extract structured data from documents
- **Research Analysis**: Semantic search across medical literature
- **Patient Communication**: Generate personalized health information
- **Data Integration**: Consolidate data from multiple sources to BigQuery

### Manufacturing
- **Document Digitization**: Process maintenance logs and manuals
- **Quality Analysis**: AI-powered defect detection insights
- **Supply Chain**: Optimize logistics with AI analysis
- **Predictive Maintenance**: Analyze sensor data in BigQuery

---

## API Reference

### Gemini API
- **Endpoint**: `https://generativelanguage.googleapis.com/v1/models/`
- **Models**: gemini-3-pro-preview, gemini-2.5-flash
- **Rate Limits**: Check GCP console for current quotas

### Vertex AI Embeddings
- **Endpoint**: `https://us-central1-aiplatform.googleapis.com/v1/`
- **Model**: textembedding-gecko@001
- **Dimensions**: 768 (default), configurable

### Document AI
- **Endpoint**: `https://documentai.googleapis.com/v1/`
- **Processors**: Invoice, Form, Receipt, Custom
- **Supported Formats**: PDF, TIFF, GIF, JPEG, PNG

### BigQuery
- **JDBC URL**: `jdbc:bigquery://https://googleapis.com/bigquery/v2`
- **Driver**: `com.google.cloud.bigquery.jdbc.Driver`
- **Authentication**: Service account or OAuth2

---

## Additional Resources

### Documentation
- [Google Cloud Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Gemini API Documentation](https://ai.google.dev/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Pentaho Documentation](https://help.hitachivantara.com/Documentation/Pentaho)

### Tutorials
- [Getting Started with Vertex AI](https://cloud.google.com/vertex-ai/docs/start/introduction-unified-platform)
- [Gemini Quickstart](https://ai.google.dev/tutorials/get_started)
- [BigQuery ETL Best Practices](https://cloud.google.com/bigquery/docs/best-practices-etl)

### Support
- [Google Cloud Support](https://cloud.google.com/support)
- [Pentaho Community](https://community.hitachivantara.com/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/pentaho)

---

## Version History

### Version 1.0
- Initial release
- Gemini AI integration examples
- Vertex AI embeddings support
- Document AI processing
- BigQuery connectivity
- Utility transformations

---

## Contributing

To contribute to this demonstration pack:

1. Fork the repository
2. Create a feature branch
3. Add or improve examples
4. Test thoroughly with your GCP environment
5. Document any new parameters or configurations
6. Submit a pull request

---

## License

This demonstration pack is provided as-is for educational and demonstration purposes. Please refer to your Pentaho and Google Cloud Platform license agreements for usage terms.

---

## Contact

For questions or support with these examples, please contact your Pentaho Solution Engineering team or open an issue in the repository.

---

**Note**: Remember to replace placeholder values (API keys, project IDs, etc.) with your actual configuration before running these transformations. Never commit sensitive credentials to version control.
