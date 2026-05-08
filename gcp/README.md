# Google Cloud Platform (GCP) Integration Project

## Overview

This project provides sample Pentaho Data Integration transformations and utilities for integrating with Google Cloud Platform services, including:

- **Document AI** - Intelligent document processing and OCR
- **Gemini AI** - Advanced language model for content generation
- **Vertex AI** - Text embedding generation for semantic search
- **BigQuery** - Data warehouse integration

The project is organized into `main` (sample components) and `examples` (reference implementations and testing utilities).

---

## Project Structure

```
gcp/
├── main/              # Sample transformations and jobs
├── examples/          # Reference implementations and tests
└── data/              # Sample data and test files
```

---

## Main Components

The `main` directory contains sample transformations and scripts that have been tested and optimized for use in real data pipelines.

### 1. `process-document-documentai.ktr`

**Purpose:** Sample transformation for processing documents using Google Cloud Document AI service. Collects files, encodes them, sends to Document AI API, and parses the response.

**Features:**
- Automated file discovery and processing
- Intelligent document parsing with OCR
- Structured data extraction from unstructured documents
- Support for various document types (invoices, forms, receipts, contracts)
- Direct GCP authentication via `gcloud auth`
- Integration with base64-encode.sh for binary file encoding
- REST API integration with authorization headers
- JSON response parsing and entity extraction
- Error handling and validation

**Parameters:**
| Parameter | Description | Default/Example |
|-----------|-------------|---------|
| `PROJECT_HOME` | Root directory for the GCP project | `/Users/khaas/icloud/Personal/Projects/solution-engineering/gcp` |
| `DOCUMENTAI_PROJECT_ID` | GCP project ID (numeric) for Document AI | `698840710107` |
| `DOCUMENTAI_PROCESSOR_ID` | Document AI processor ID | `887efdad199b93b9` |
| `MODEL_URL` | Full Document AI processor endpoint URL (auto-constructed) | `https://us-documentai.googleapis.com/v1/projects/${DOCUMENTAI_PROJECT_ID}/locations/us/processors/${DOCUMENTAI_PROCESSOR_ID}:process` |

**Note:** The `MODEL_URL` is dynamically constructed from `DOCUMENTAI_PROJECT_ID` and `DOCUMENTAI_PROCESSOR_ID`, so you only need to set those two parameters in most cases.

**Transformation Steps:**
1. **Get file names** - Scans `${PROJECT_HOME}/data` directory recursively for documents
2. **Get variables** - Loads base64-encode.sh path and JSON body template
3. **Get variables for gcp** - Retrieves GCP MODEL_URL and generates auth token via gcloud
4. **Join rows** - Combines file list with GCP configuration (cartesian product)
5. **Base64 Encode** - Calls `base64-encode.sh` to encode each PDF file
6. **Format Auth** - Constructs Authorization header (`Bearer {token}`) and JSON request body
7. **Process Document** - Sends POST request to Document AI REST API with base64 content
8. **Parse Output** - Extracts `$.document.entities` array from JSON response
9. **Entities JSON** - Filters output to include filename and extracted entities
10. **Output** - Returns processed results for downstream steps

**Input Requirements:**
- Place PDF files in `${PROJECT_HOME}/data/` directory
- Must have valid GCP authentication: `gcloud auth login` with active session
- Document AI processor must be created in GCP project

**Output Fields:**
- `filename` - Name of processed document
- `entities` - Extracted entities as JSON array with:
  - `type` - Entity classification (e.g., "invoice_number", "total_amount")
  - `mentionText` - Recognized text value
  - `confidence` - AI confidence score (0-1)
  - `normalizedValue` - Standardized/parsed value

**Processing Workflow:**
```
Files in /data → Discover → Auth → Base64 Encode → REST Call → Parse JSON → Extract Entities → Output
```

**Configuration Example:**
```bash
# Ensure you have valid token:
gcloud auth login
gcloud auth print-access-token  # Should return valid JWT token
```

**Supported Document Types from DocumentAI:**
- **Invoices:** Extracts invoice #, date, amount, line items
- **Forms:** Parses structured form fields
- **Receipts:** Extracts merchant, items, totals, tax
- **Contracts:** Identifies parties, dates, key clauses
- **General OCR:** Full text extraction with character positions

**Error Handling:**
- **File not found:** Check `${PROJECT_HOME}/data` directory exists and contains PDFs
- **Authentication error:** Run `gcloud auth login` to refresh token (valid ~1 hour)
- **Processor error:** Verify MODEL_URL matches existing processor in same GCP project
- **API errors:** Check transformation logs for specific Document AI error messages
- **Empty results:** Ensure document quality is sufficient for OCR processing

**Performance Characteristics:**
- **Processing time:** ~2-10 seconds per document (synchronous)
- **Parallel copies:** Uses 2 copies of Process Document step for concurrent API calls
- **File limit:** No explicit limit; respects GCP quota of ~15 pages/min synchronously
- **Memory:** Streams responses; minimal memory overhead per document

**Best Practices:**
1. **Organize files:** Group similar document types in separate subdirectories
2. **Monitor tokens:** Token expires in ~1 hour; re-run `gcloud auth login` if needed
3. **Batch size:** Process 10-100 documents at a time for optimal throughput
4. **Testing:** Test with small PDF first before full deployment
5. **Cleanup:** Remove processed files from data directory to avoid reprocessing

---

### 2. `base64-encode.sh`

**Purpose:** Utility script for encoding files to base64 format, required for sending binary files to Google Cloud AI APIs.

**Features:**
- Accepts full file path as parameter
- Automatic parameter validation and file existence checking
- Strips surrounding quotes (handles Pentaho parameter edge cases)
- Removes newlines from encoded output (API-ready format)
- Clear error messages for troubleshooting

**Usage:**
```bash
# From command line
./base64-encode.sh /path/to/document.pdf

# From Pentaho transformation (Execute Row SQL Script step or Shell step)
${BASE64_ENCODE_SCRIPT} ${FILE_PATH}
```

**Supported File Types:**
- **Documents:** PDF, Word (.doc, .docx), Excel (.xls, .xlsx), PowerPoint, Text
- **Images:** JPEG, PNG, GIF, TIFF, BMP, WEBP, SVG
- **Any binary file** that needs to be sent to GCP APIs

**Integration Notes:**
- When calling from Pentaho, pass parameters WITHOUT quotes: `${FILE_PATH}` (not `'${FILE_PATH}'`)
- Script automatically handles quote stripping to prevent double-quoting issues
- Output is a single-line base64 string suitable for JSON API payloads
- Essential for Document AI and Gemini vision/multimodal processing

**Error Handling:**
- Returns exit code 1 if file not found or no parameter provided
- Provides clear error messages to stderr
- Logs actual file path attempted for debugging

**Technical Details:**
```bash
# The script uses:
# - base64 -i for input file encoding
# - tr -d '\n' to remove newlines (required for API JSON)
# - Bash parameter expansion for quote stripping
```

**Alternative: GenAI Base64 Encoding Plugin**

> **Note:** As an alternative to this shell script, Pentaho's GenAI plugin provides native base64 encoding capabilities without requiring external shell execution. This can be advantageous for:
> - Cross-platform compatibility (Windows, Linux, macOS)
> - Reduced dependency on bash/shell scripting
> - Better error handling within Pentaho transformations
> - Simplified testing and debugging in the Pentaho UI
> 
> If your Pentaho environment has the GenAI plugin installed, consider using its encoding features instead of this script for new transformations.

---

## Examples Directory

The `examples` directory contains reference implementations, test utilities, and demonstrations of GCP service integration patterns. These are ideal for learning, testing, and as templates for building custom solutions.

### Quick Reference

| File | Purpose | GCP Service |
|------|---------|-------------|
| `generate-response-gemini.ktr` | AI text generation | Gemini API |
| `generate-response-gemini-websearch.ktr` | AI with web search | Gemini + Search |
| `generate-embedding-vertex.ktr` | Vector embeddings | Vertex AI |
| `process-document-documentai.ktr` | Document processing | Document AI |
| `bigquery-loader.kjb` | Data warehouse loading | BigQuery |
| `biqquery-jdbc-connect-test.ktr` | Connection testing | BigQuery JDBC |
| `command-test.ktr` | API testing | Gemini API |
| `increment-count.ktr` | Retry logic utility | N/A |

### Key Examples

#### AI and ML Services
- **Gemini AI Integration**: Text generation with configurable context and parameters
- **Web-Enhanced AI**: Gemini with real-time web search for current information
- **Vector Embeddings**: Generate 768-dimension embeddings for semantic search
- **Document AI**: Example document processing with different processor types

#### Data Integration
- **BigQuery Loader**: Orchestrated job for loading data into BigQuery
- **JDBC Testing**: Validate BigQuery connectivity and configuration

#### Testing and Utilities
- **Command Test**: Quick API validation and troubleshooting
- **Retry Logic**: Counter-based retry pattern for resilient pipelines

For detailed information about each example, see [examples/README.md](examples/README.md).

---

## Prerequisites

### 1. Google Cloud Platform Setup

> **⚠️ IMPORTANT: Corporate Authentication**
> 
> When working with HitachiVantara GCP resources:
> 1. **Use your @hitachivantara.com account** (NOT personal Google account)
> 2. **Authenticate through Okta first:**
>    - Log in to Google Workspace via Okta
>    - Open Google Cloud Console from the authenticated browser session
> 3. **Then run gcloud auth** from the same authenticated session
> 
> This ensures proper SSO authentication and access to corporate GCP projects.

```bash
# Install Google Cloud SDK
# Visit: https://cloud.google.com/sdk/docs/install

# Authenticate with your @hitachivantara.com account
gcloud auth login

# IMPORTANT: Select your @hitachivantara.com account when the browser opens
# Make sure you're already authenticated via Okta/Google Workspace

# Set project (example: hv-pentaho-dev-connectivity)
gcloud config set project YOUR_PROJECT_ID

# Verify authentication and project
gcloud config list

# Get access token for API calls
gcloud auth print-access-token
```

### 2. Enable Required APIs
```bash
# Document AI
gcloud services enable documentai.googleapis.com

# Vertex AI (for embeddings)
gcloud services enable aiplatform.googleapis.com

# Gemini AI
gcloud services enable generativelanguage.googleapis.com

# BigQuery
gcloud services enable bigquery.googleapis.com
```

### 3. Pentaho Data Integration
- **Version:** PDI 9.x or later recommended
- **Required Plugins:** REST Client, JSON Input/Output
- **Java:** JDK 8 or 11

### 4. Create Document AI Processors
```bash
# Navigate to Document AI console
# https://console.cloud.google.com/ai/document-ai

# Create processors for your use cases:
# - Form Parser
# - Invoice Parser
# - Receipt Parser
# - General Document OCR
```

---

## Getting Started

### 1. Test Authentication
```bash
# Get access token
TOKEN=$(gcloud auth print-access-token)
echo $TOKEN

# Token is valid for ~1 hour
# Re-run this command when token expires
```

### 2. Test Base64 Encoding
```bash
cd main

# Test the script
./base64-encode.sh ../data/pentaho-genai.pdf

# You should see base64 encoded output
# No errors = success
```

### 3. Run Example Transformation
```bash
# Open Pentaho Spoon
./spoon.sh

# Open: examples/command-test.ktr
# This is the simplest example - tests Gemini API

# Set variables:
# - TOKEN: Your gcloud access token
# - PROMPT: "Tell me a joke"

# Run the transformation
# Expected: JSON response with AI-generated joke
```

### 4. Process a Document
```bash
# Open: main/process-document-documentai.ktr

# Configure parameters:
# - FILE_PATH: /full/path/to/your/document.pdf
# - PROJECT_ID: your-gcp-project-id
# - PROCESSOR_ID: your-processor-id
# - LOCATION: us (or eu)
# - TOKEN: $(gcloud auth print-access-token)

# Run transformation
# Review extracted text and entities in output
```

---

## Common Patterns

### Token Management in Pentaho
```javascript
// Get Job Entry - Execute Shell Script
// Script:
gcloud auth print-access-token

// Capture output to variable: ${TOKEN}
// Set result variable name: TOKEN

// Then use ${TOKEN} in subsequent steps
```

### File Path Handling
```javascript
// In Pentaho, use absolute paths:
${Internal.Transformation.Filename.Directory}/../data/myfile.pdf

// Or set as job parameter:
FILE_PATH = /full/path/to/file.pdf

// Pass to shell script WITHOUT quotes:
${BASE64_SCRIPT} ${FILE_PATH}
```

### Error Handling Pattern
```javascript
// 1. Try transformation
// 2. If error, increment retry counter
// 3. Sleep (exponential backoff)
// 4. Retry if counter < MAX_RETRIES
// 5. Log failure if max retries exceeded

// See: examples/increment-count.ktr
```

---

## API Quotas and Limits

### Document AI
- **Synchronous:** 15 pages/min, 20 MB max file size
- **Asynchronous:** 1,000 pages/day (free tier)
- **Paid tier:** Higher quotas available

### Gemini API
- **Free tier:** 15 requests/minute
- **Paid tier:** 360 requests/minute
- **Rate limiting:** Implement backoff on 429 errors

### Vertex AI Embeddings
- **Quota:** 600 requests/minute
- **Batch size:** Up to 5 text items per request
- **Dimensions:** 768 (text-embedding-gecko)

---

## Troubleshooting

### Issue: "File not found" in Pentaho
**Solution:**
- Remove quotes from parameter: Use `${FILE_PATH}` not `'${FILE_PATH}'`
- Verify absolute path: Check file exists at specified location
- Check permissions: Ensure Pentaho can read the file

### Issue: "Authentication failed"
**Solution:**
```bash
# Re-authenticate
gcloud auth login

# Verify token
gcloud auth print-access-token

# Check token hasn't expired (valid for ~1 hour)
```

### Issue: "Processor not found"
**Solution:**
- Verify processor ID is correct
- Check processor location matches LOCATION parameter
- Ensure processor is in the same project as PROJECT_ID

### Issue: Rate limit errors (429)
**Solution:**
- Implement exponential backoff
- Reduce request rate
- Consider upgrading to paid tier
- Use batch processing for Document AI

---

## Best Practices

### Security
1. **Never commit tokens or credentials** to version control
2. **Use service accounts** for production deployments
3. **Rotate tokens regularly** (automatic with gcloud)
4. **Restrict API access** using IAM policies

### Performance
1. **Batch processing:** Group similar documents together
2. **Parallel execution:** Process multiple files concurrently
3. **Caching:** Store processed results to avoid reprocessing
4. **Async processing:** Use for large documents or high volumes

### Cost Optimization
1. **Right-size processors:** Use appropriate processor for document type
2. **Monitor usage:** Set up billing alerts
3. **Free tier:** Leverage free quotas for development/testing
4. **Batch vs real-time:** Choose based on latency requirements

---

## Additional Resources

- [Google Cloud Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Gemini API Documentation](https://ai.google.dev/docs)
- [Vertex AI Embeddings Guide](https://cloud.google.com/vertex-ai/docs/generative-ai/embeddings/get-text-embeddings)
- [BigQuery Integration Guide](https://cloud.google.com/bigquery/docs)
- [Pentaho Documentation](https://help.hitachivantara.com/Documentation/Pentaho)

---

## Contributing

When adding new transformations or utilities:
1. Place components in `main/`
2. Place examples and tests in `examples/`
3. Update this README with component details
4. Include error handling and parameter validation
5. Document all parameters and use cases

---

## License

Refer to repository license file.

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review examples for reference implementations
3. Consult GCP documentation for API-specific issues
4. Contact your GCP support representative for quota/billing questions
