# Aperture

AI model integration and Pentaho Data Integration (PDI) pipelines for Solution Engineering. This project contains ready-to-run KTR/KJB jobs for Azure (Cognitive Search/Function flows), Google Vertex/Gemini, AWS Bedrock, OpenAI, plus shared resources and examples.

## Project Structure

```
aperture/
├── azure/                 # Azure-focused PDI jobs and transformations
│   ├── lead-generation-main.kjb
│   ├── main.kjb
│   ├── main-call.kjb
│   ├── *.ktr (load, reset, assign, generate)
│   └── archive/
├── bedrock/               # AWS Bedrock model calls and shell wrappers
│   ├── call-bedrock.sh
│   ├── call-custom-aws.sh
│   ├── base64-encode.sh
│   └── call-bedrock-models.ktr
├── gemini/                # Google Vertex/Gemini integrations (comprehensive)
│   ├── bigquery-loader.kjb                     # Load data/results into BigQuery
│   ├── biqquery-jdbc-connect-test.ktr          # JDBC connectivity test to BigQuery
│   ├── command-test.ktr                        # Invoke Vertex/Gemini via command pattern
│   ├── generate-embedding-vertex.ktr          # Generate embeddings with Vertex AI
│   ├── generate-response-gemini.ktr           # Text generation with Gemini
│   ├── generate-response-gemini-websearch.ktr # Gemini with web search augmentation
│   ├── process-document-documentai.ktr        # Google Document AI processing pipeline
│   ├── Job 1.kjb                               # Sample job wrapper
│   ├── gemini-model-commands/                  # Sample CLI commands for Gemini models
│   ├── gemini-vector-store-cross-product-analysis/ # Vector store example/analysis
│   └── samples/                                # Additional sample KTR/KJB
├── openai/                # OpenAI integration jobs
│   └── generate-raw-lead-openai.ktr
├── transformations/       # General transformations (samples and utilities)
│   └── samples/
├── jobs/                  # General jobs (gitkeep placeholder)
├── shared/                # Shared resources (gitkeep placeholder)
├── .github/               # Copilot instructions and repo config
├── .meta/                 # Metastore (PDI repository metadata)
├── aws-model-commands     # Sample model CLI commands
├── gemini-model-commands  # Gemini model command samples
├── mixtral-model-commands # Mixtral model command samples
├── sample-repo-sql.sql    # Example SQL for repository
├── foundation-models.json # Foundation model catalog/sample
├── request.json           # Example model request
├── body.json              # Example body payload
├── signed_headers.json    # Example signed header payload
├── out*.json / out*.txt   # Example outputs
├── sample.pdf             # Sample input PDF for doc processing
└── pentaho-connectivity-*.json # Local connectivity credentials (do not commit)
```

## Prerequisites

- Pentaho Data Integration 10.x+ (Spoon or Carte)
- Access credentials and API keys for the target providers: Azure, Google Cloud, AWS, OpenAI
- Configure `.python-version` for any Python helpers if required
- Ensure secrets are ignored by Git (see `.gitignore`)

## Setup

1. Open Spoon and set the repository to point to this folder or import the KTR/KJB files.
2. Configure connections/variables:
	- Azure: storage, search, function endpoints as used by `azure/*.ktr`
	- Google: Vertex AI/Gemini credentials (Application Default Credentials or service account)
	- AWS: Bedrock permissions; update shell scripts in `bedrock/`
	- OpenAI: API key environment variable
3. Validate any JDBC connections referenced by sample transformations.

## Usage Examples

### Azure Lead Generation Flow
- `azure/lead-generation-main.kjb` orchestrates the lead-generation pipeline.
- Supporting steps include `load-account-owners.ktr`, `generate-raw-lead-azure.ktr`, and `assign-run-id.ktr`.

### AWS Bedrock Calls
```bash
cd bedrock
./call-bedrock.sh          # Basic Bedrock invocation
./call-custom-aws.sh       # Custom signing/example flow
```

Run `call-bedrock-models.ktr` from Spoon to test individual model calls.

### Google Gemini / Vertex
- Use `gemini/generate-response-gemini.ktr` for text generation
- `gemini/generate-embedding-vertex.ktr` for embeddings
- `gemini/bigquery-loader.kjb` to load results into BigQuery

### OpenAI
- `openai/generate-raw-lead-openai.ktr` demonstrates a simple ingest + model call pattern

## Notes & Best Practices

- Keep transformation/job files organized by provider and function
- Document required environment variables and connection configs near each transformation
- Avoid committing secrets: use `.gitignore` and local-only JSON key files
- Prefer parameterized KTR/KJB with variables over hard-coded endpoints

## Security & Git Hygiene

- `.gitignore` should exclude `pentaho-connectivity-*.json`, credentials, tokens, and generated outputs
- Review `.meta/metastore/` contents before committing if it contains environment-specific metadata

## References

- Pentaho/GIS pipelines: `Pentaho_Google_AI_Pipeline.pptx`, `loan_ai_pipeline_diagram.pptx`
- Command samples: `aws-model-commands/`, `gemini-model-commands/`, `mixtral-model-commands/`
