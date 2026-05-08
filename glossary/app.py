from flask import Flask, jsonify, request
import os
import json
import logging
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.exc import SQLAlchemyError
import traceback
from datetime import datetime
import httpx
from typing import Dict, Any
import time
from dotenv import load_dotenv

# Load environment variables from .env file (for local development)
load_dotenv()

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

# Global variables for lazy loading
_db_engine = None
_config = None
_prompts = None

def load_prompts():
    """Load prompt templates from prompts.json file"""
    global _prompts
    if _prompts is not None:
        return _prompts
    
    try:
        with open('prompts.json', 'r') as f:
            _prompts = json.load(f)
        logger.info("Prompt templates loaded successfully")
        return _prompts
    except FileNotFoundError:
        logger.warning("prompts.json not found, using default prompt")
        _prompts = {
            "default": {
                "name": "Default Business Glossary",
                "description": "Default business glossary generator",
                "template": ('Analyze this database schema and create a comprehensive business data glossary. '
                           'Based on the table names, column names, and their relationships, analyze the business at hand, '
                           'and organize the business terms into a hierarchical structure. '
                           'Return ONLY valid JSON in this exact format: '
                           '{{ "Root Glossary Name": [ {{ "Category Under Root": [ "Simple Leaf Term", '
                           '{{ "Parent Leaf Term": [ "Nested Leaf Term" ] }} ] }} ] }}. '
                           'Use meaningful business terms derived from the schema. Schema to analyze: {schema_summary}')
            }
        }
        return _prompts
    except Exception as e:
        logger.error(f"Error loading prompt templates: {e}")
        return None

def load_config():
    """Load configuration from environment variables with defaults (lazy loading)"""
    global _config
    if _config is not None:
        return _config
    
    try:
        # Load all configuration from environment variables with sensible defaults
        _config = {
            # Database configuration
            'database_url': os.getenv('DATABASE_URL'),
            'database_schema': os.getenv('DATABASE_SCHEMA'),
            
            # API configuration
            'api_base_url': os.getenv('API_BASE_URL'),
            'api_key': os.getenv('API_KEY'),
            'api_deployment_id': os.getenv('API_DEPLOYMENT_ID', 'model-router'),
            'api_version': os.getenv('API_VERSION', '2025-01-01-preview'),
            
            # AI model configuration with defaults
            'api_max_tokens': int(os.getenv('API_MAX_TOKENS', '8192')),
            'api_temperature': float(os.getenv('API_TEMPERATURE', '0.7')),
            'api_timeout': float(os.getenv('API_TIMEOUT', '60.0')),
            'api_max_retries': int(os.getenv('API_MAX_RETRIES', '3')),
            
            # Server configuration
            'port': int(os.getenv('PORT', '5000'))
        }
        
        # Validate required configuration
        required_vars = ['database_url', 'api_base_url', 'api_key']
        missing_vars = [var for var in required_vars if not _config.get(var)]
        
        if missing_vars:
            logger.error(f"Missing required environment variables: {', '.join(missing_vars)}")
            logger.error("Please check your environment configuration or .env file")
            return None
        
        logger.info("Configuration loaded successfully from environment variables")
        return _config
        
    except Exception as e:
        logger.error(f"Error loading configuration: {e}")
        return None

def transform_to_csv(hierarchical_data):
    """Transform hierarchical glossary data directly to CSV format without AI"""
    import csv
    import io
    from datetime import datetime
    
    # CSV headers for PDC format
    headers = ['_id','name','type','fqdn','parentId','rootId','resourceId','createdAt','updatedAt','createdBy','updatedBy','attributes']
    
    # Prepare CSV data
    rows = []
    current_time = datetime.utcnow().isoformat() + 'Z'
    
    def generate_guid():
        import uuid
        return str(uuid.uuid4())
    
    def process_hierarchy(data, parent_id=None, root_id=None, parent_fqdn=""):
        """Recursively process the hierarchical data structure"""
        
        if isinstance(data, dict):
            for key, value in data.items():
                # Generate IDs
                item_id = generate_guid()
                current_root_id = root_id if root_id else item_id
                
                # Build FQDN with forward slashes
                if parent_fqdn:
                    fqdn = f"{parent_fqdn}/{key}"
                else:
                    fqdn = key
                
                # Determine type based on hierarchy level and content (lowercase)
                if parent_id is None:
                    item_type = "glossary"
                elif isinstance(value, list) and any(isinstance(item, dict) for item in value):
                    item_type = "category"
                else:
                    item_type = "term"
                
                # Create attributes with proper JSON escaping
                attributes = '{"info":{"status":"Draft"}}'
                
                # Add row
                row = [
                    item_id,                    # _id
                    key,                        # name
                    item_type,                  # type
                    fqdn,                       # fqdn
                    parent_id or '',            # parentId
                    current_root_id,            # rootId
                    '',                         # resourceId
                    current_time,               # createdAt
                    current_time,               # updatedAt
                    'system',                   # createdBy
                    'system',                   # updatedBy
                    attributes                  # attributes
                ]
                rows.append(row)
                
                # Process children
                if isinstance(value, list):
                    for item in value:
                        process_hierarchy(item, item_id, current_root_id, fqdn)
                elif isinstance(value, dict):
                    process_hierarchy(value, item_id, current_root_id, fqdn)
        
        elif isinstance(data, list):
            for item in data:
                process_hierarchy(item, parent_id, root_id, parent_fqdn)
        
        elif isinstance(data, str):
            # This is a leaf term
            item_id = generate_guid()
            current_root_id = root_id if root_id else item_id
            
            # Build FQDN with forward slashes
            if parent_fqdn:
                fqdn = f"{parent_fqdn}/{data}"
            else:
                fqdn = data
            
            # Create attributes with proper JSON escaping
            attributes = '{"info":{"status":"Draft"}}'
            
            # Add row
            row = [
                item_id,                    # _id
                data,                       # name
                "term",                     # type (lowercase)
                fqdn,                       # fqdn
                parent_id or '',            # parentId
                current_root_id,            # rootId
                '',                         # resourceId
                current_time,               # createdAt
                current_time,               # updatedAt
                'system',                   # createdBy
                'system',                   # updatedBy
                attributes                  # attributes
            ]
            rows.append(row)
    
    # Process the input data
    process_hierarchy(hierarchical_data)
    
    # Generate CSV
    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(headers)
    writer.writerows(rows)
    
    return output.getvalue()

def get_database_engine():
    """Get database engine with lazy loading and connection pooling"""
    global _db_engine
    if _db_engine is not None:
        return _db_engine
    
    try:
        config = load_config()
        if not config or not config.get('database_url'):
            logger.error("No database URL configured")
            return None
        
        # Create engine with connection timeout and retry logic
        _db_engine = create_engine(
            config['database_url'],
            pool_timeout=10,
            pool_recycle=3600,
            pool_pre_ping=True,
            connect_args={"connect_timeout": 10}
        )
        
        # Test connection
        with _db_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        
        logger.info("Database connection established successfully")
        return _db_engine
        
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        _db_engine = None
        return None

def clean_and_validate_json(response_text: str) -> dict:
    """Clean API response and validate it's proper JSON."""
    if not response_text:
        return None
    
    # Remove markdown code blocks if present
    cleaned_text = response_text.strip()
    
    # Remove ```json and ``` markers
    if cleaned_text.startswith('```json'):
        cleaned_text = cleaned_text[7:]  # Remove ```json
    elif cleaned_text.startswith('```'):
        cleaned_text = cleaned_text[3:]   # Remove ```
    
    if cleaned_text.endswith('```'):
        cleaned_text = cleaned_text[:-3]  # Remove trailing ```
    
    cleaned_text = cleaned_text.strip()
    
    # Try to parse as JSON
    try:
        json_obj = json.loads(cleaned_text)
        logger.info("Successfully parsed and validated JSON response")
        return json_obj
    except json.JSONDecodeError as e:
        logger.warning(f"Invalid JSON in API response: {e}")
        return None

def make_api_call(schema_summary: str, api_config: dict = None, prompt_template_name: str = "default") -> dict:
    """Make an API call with the schema summary and configured prompt."""
    config = load_config()
    if not config:
        logger.error("No configuration available")
        return None
    
    # Start with defaults from environment configuration
    default_api_config = {
        'base_url': config.get('api_base_url'),
        'api_key': config.get('api_key'),
        'deployment_id': config.get('api_deployment_id', 'model-router'),
        'api_version': config.get('api_version', '2025-01-01-preview'),
        'max_tokens': config.get('api_max_tokens', 8192),
        'temperature': config.get('api_temperature', 0.7),
        'timeout': config.get('api_timeout', 60.0),
        'max_retries': config.get('api_max_retries', 3),
        'top_p': 0.95,
        'frequency_penalty': 0,
        'presence_penalty': 0,
        'model': 'model-router'
    }
    
    # Merge with any provided overrides
    if api_config:
        # Update defaults with any provided overrides
        default_api_config.update(api_config)
    
    # Use the merged configuration
    api_config = default_api_config
    
    base_url = api_config.get('base_url')
    deployment_id = api_config.get('deployment_id', 'model-router')
    api_version = api_config.get('api_version', '2025-01-01-preview')
    api_key = api_config.get('api_key')
    max_retries = api_config.get('max_retries', 3)
    
    if not all([base_url, api_key]):
        logger.error("Missing required API configuration (base_url, api_key)")
        return None
    
    # Load prompt template from prompts.json
    prompts = load_prompts()
    if not prompts:
        logger.error("Failed to load prompt templates")
        return None
    
    # Get the specified prompt template
    if prompt_template_name not in prompts:
        logger.error(f"Prompt template '{prompt_template_name}' not found in prompts.json")
        return None
    
    prompt_info = prompts[prompt_template_name]
    prompt_template = prompt_info["template"]
    
    logger.info(f"Using prompt template: {prompt_info['name']} - {prompt_info['description']}")
    
    formatted_prompt = prompt_template.format(schema_summary=schema_summary)
    
    # Log the first 300 characters of the formatted prompt for debugging
    logger.info(f"Generated prompt for AI ({len(formatted_prompt)} chars): {formatted_prompt[:300]}{'...' if len(formatted_prompt) > 300 else ''}")
    
    message = {
        "messages": [
            {
                "role": "user",
                "content": formatted_prompt
            }
        ],
        "max_tokens": api_config.get("max_tokens", 8192),
        "temperature": api_config.get("temperature", 0.7),
        "top_p": api_config.get("top_p", 0.95),
        "frequency_penalty": api_config.get("frequency_penalty", 0),
        "presence_penalty": api_config.get("presence_penalty", 0),
        "model": api_config.get("model", "model-router")
    }
    
    for attempt in range(1, max_retries + 1):
        logger.info(f"Making API call attempt {attempt}/{max_retries} to: {base_url}")
        
        try:
            response = httpx.post(
                f'http://{base_url}/deployments/{deployment_id}/chat/completions?api-version={api_version}',
                headers={
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Credentials': 'true',
                    'api-key': api_key
                },
                json=message,
                timeout=api_config.get("timeout", 60.0)
            )
            
            logger.info(f"API response status: {response.status_code}")
            
            if response.status_code == 200:
                logger.info(f"API call attempt {attempt} successful")
                response_data = response.json()
                content = response_data.get("choices", [{}])[0].get("message", {}).get("content", "")
                
                # Log the first 200 characters of the response for debugging
                logger.info(f"AI response received ({len(content)} chars): {content[:200]}{'...' if len(content) > 200 else ''}")
                
                # Clean and validate JSON
                parsed_json = clean_and_validate_json(content)
                if parsed_json is not None:
                    logger.info(f"Valid JSON parsed successfully on attempt {attempt}")
                    return parsed_json
                else:
                    logger.warning(f"Invalid JSON received on attempt {attempt}, retrying...")
                    if attempt < max_retries:
                        # Modify the prompt slightly for retry to encourage better JSON
                        message["messages"][0]["content"] = formatted_prompt + " Please ensure your response is valid JSON only, without any markdown formatting or extra text."
                    continue
            else:
                logger.error(f"API call attempt {attempt} failed with status {response.status_code}: {response.text}")
                if attempt < max_retries:
                    continue
                
        except Exception as e:
            logger.error(f"API call attempt {attempt} error: {e}")
            if attempt < max_retries:
                continue
    
    logger.error(f"All {max_retries} API call attempts failed")
    return None

def make_api_call_for_generate(input_data: str, api_config: dict = None, prompt_template_name: str = 'generate'):
    """Make API call for generate endpoint with input data transformation."""
    
    # Load configuration
    config = load_config()
    if not config:
        logger.error("Failed to load configuration")
        return None
    
    # Set up default API configuration from environment
    default_api_config = {
        'base_url': config.get('api_base_url'),
        'api_key': config.get('api_key'),
        'deployment_id': config.get('api_deployment_id', 'model-router'),
        'api_version': config.get('api_version', '2025-01-01-preview'),
        'max_tokens': config.get('api_max_tokens', 8192),
        'temperature': config.get('api_temperature', 0.7),
        'timeout': config.get('api_timeout', 60.0),
        'max_retries': config.get('api_max_retries', 3),
        'top_p': 0.95,
        'frequency_penalty': 0,
        'presence_penalty': 0,
        'model': 'model-router'
    }
    
    # Merge with any provided overrides
    if api_config:
        default_api_config.update(api_config)
    
    # Use the merged configuration
    api_config = default_api_config
    
    base_url = api_config.get('base_url')
    deployment_id = api_config.get('deployment_id', 'model-router')
    api_version = api_config.get('api_version', '2025-01-01-preview')
    api_key = api_config.get('api_key')
    max_retries = api_config.get('max_retries', 3)
    
    if not all([base_url, api_key]):
        logger.error("Missing required API configuration (base_url, api_key)")
        return None
    
    # Load prompt template from prompts.json
    prompts = load_prompts()
    if not prompts:
        logger.error("Failed to load prompt templates")
        return None
    
    # Get the specified prompt template
    if prompt_template_name not in prompts:
        logger.error(f"Prompt template '{prompt_template_name}' not found in prompts.json")
        return None
    
    prompt_info = prompts[prompt_template_name]
    prompt_template = prompt_info["template"]
    
    logger.info(f"Using prompt template: {prompt_info['name']} - {prompt_info['description']}")
    
    formatted_prompt = prompt_template.format(input_data=input_data)
    
    # Log the first 300 characters of the formatted prompt for debugging
    logger.info(f"Generated prompt for AI ({len(formatted_prompt)} chars): {formatted_prompt[:300]}{'...' if len(formatted_prompt) > 300 else ''}")
    
    message = {
        "messages": [
            {
                "role": "user",
                "content": formatted_prompt
            }
        ],
        "max_tokens": api_config.get("max_tokens", 8192),
        "temperature": api_config.get("temperature", 0.7),
        "top_p": api_config.get("top_p", 0.95),
        "frequency_penalty": api_config.get("frequency_penalty", 0),
        "presence_penalty": api_config.get("presence_penalty", 0),
        "model": api_config.get("model", "model-router")
    }
    
    for attempt in range(1, max_retries + 1):
        logger.info(f"Making API call attempt {attempt}/{max_retries} to: {base_url}")
        
        try:
            response = httpx.post(
                f'http://{base_url}/deployments/{deployment_id}/chat/completions?api-version={api_version}',
                headers={
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Credentials': 'true',
                    'api-key': api_key
                },
                json=message,
                timeout=api_config.get('timeout', 60.0)
            )
            
            response.raise_for_status()
            response_data = response.json()
            
            logger.info("API call successful")
            content = response_data.get('choices', [{}])[0].get('message', {}).get('content', '')
            
            try:
                # For generate endpoint, detect the output format
                if prompt_template_name == 'generate':
                    content_stripped = content.strip()
                    
                    # Check if it's CSV format (starts with _id,name,type,fqdn...)
                    if content_stripped.startswith('_id,name,type,fqdn') or content_stripped.startswith('"_id","name","type","fqdn"'):
                        logger.info("Response detected as CSV format")
                        return {"csv_content": content_stripped}
                    
                    # Try JSON Lines format
                    lines = content_stripped.split('\n')
                    parsed_objects = []
                    for line in lines:
                        if line.strip():
                            try:
                                parsed_objects.append(json.loads(line))
                            except json.JSONDecodeError:
                                # If JSON Lines parsing fails, try regular JSON
                                pass
                    
                    if parsed_objects:
                        logger.info(f"Response successfully parsed as JSON Lines ({len(parsed_objects)} objects)")
                        # Return the raw JSON Lines text format
                        return {"json_lines_text": content_stripped}
                
                # Try to parse as regular JSON
                content_json = json.loads(content)
                logger.info("Response successfully parsed as JSON")
                return content_json
            except json.JSONDecodeError:
                logger.warning("Response is not valid JSON, returning as text")
                return {"generated_content": content}
                
        except httpx.TimeoutException:
            logger.warning(f"API call attempt {attempt} timed out")
        except httpx.HTTPStatusError as e:
            logger.error(f"API call attempt {attempt} failed with status {e.response.status_code}: {e.response.text}")
        except Exception as e:
            logger.error(f"API call attempt {attempt} failed with unexpected error: {e}")
            
        if attempt < max_retries:
            continue
    
    logger.error(f"All {max_retries} API call attempts failed")
    return None

def create_schema_summary(engine, schema_name: str = None) -> str:
    """Create a concise summary of the database schema for API consumption."""
    try:
        with engine.connect() as conn:
            inspector = inspect(engine)
            
            if schema_name:
                tables = inspector.get_table_names(schema=schema_name)
            else:
                tables = inspector.get_table_names()
            
            table_count = len(tables)
            schema_prefix = f"Schema '{schema_name}': " if schema_name else "Database: "
            
            summary_parts = [f"{schema_prefix}{table_count} tables"]
            
            # Add table details
            table_details = []
            for table_name in tables:
                columns = inspector.get_columns(table_name, schema=schema_name)
                column_names = [col['name'] for col in columns]
                
                # Limit column names to keep summary concise
                if len(column_names) > 10:
                    column_summary = f"{', '.join(column_names[:10])}... ({len(column_names)} total columns)"
                else:
                    column_summary = ', '.join(column_names)
                
                table_details.append(f"Table {table_name}: {column_summary}")
            
            summary_parts.extend(table_details)
            schema_summary = '\n'.join(summary_parts)
            
            # Log the first 500 characters of the schema summary for debugging
            logger.info(f"Generated schema summary ({len(schema_summary)} chars): {schema_summary[:500]}{'...' if len(schema_summary) > 500 else ''}")
            return schema_summary
            
    except Exception as e:
        logger.error(f"Error creating schema summary: {e}")
        return f"Error: Unable to create schema summary - {str(e)}"

@app.route('/health')
def health():
    """Health check endpoint with database connectivity test"""
    health_status = {
        "status": "healthy",
        "message": "Service is running",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "checks": {
            "service": "ok"
        }
    }
    
    # Test database connection (non-blocking)
    try:
        engine = get_database_engine()
        if engine:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            health_status["checks"]["database"] = "ok"
        else:
            health_status["checks"]["database"] = "unavailable"
            health_status["status"] = "degraded"
    except Exception as e:
        health_status["checks"]["database"] = f"error: {str(e)[:100]}"
        health_status["status"] = "degraded"
    
    return jsonify(health_status)

@app.route('/')
def home():
    """Basic home endpoint with configuration info"""
    config = load_config()
    
    return jsonify({
        "service": "Database Schema Glossary Generator",
        "status": "running",
        "version": "v2.1-unified-config-static",
        "endpoints": [
            "/health - Health check with database connectivity",
            "/config - Complete configuration with sources (env vars vs defaults)",
            "/analyze - POST: Generate AI-powered business glossary from database schema",
            "/generate - POST: Transform glossary data to PDC-compatible CSV format",
            "/docs - API documentation"
        ],
        "database_configured": bool(config and config.get('database_url')),
        "api_configured": bool(config and config.get('api_base_url') and config.get('api_key'))
    })

@app.route('/config')
def show_config():
    """Show complete configuration with sources and security masking"""
    config = load_config()
    
    if not config:
        return jsonify({
            "error": "Configuration not loaded",
            "message": "Please check your environment variables or .env file",
            "required_env_vars": ["DATABASE_URL", "API_BASE_URL", "API_KEY"],
            "help": "Copy .env.example to .env and fill in your values"
        }), 500
    
    # Track which values come from environment vs defaults
    config_with_sources = {}
    
    # Check each config value against environment variables
    env_mapping = {
        'database_url': 'DATABASE_URL',
        'database_schema': 'DATABASE_SCHEMA', 
        'api_base_url': 'API_BASE_URL',
        'api_key': 'API_KEY',
        'api_deployment_id': 'API_DEPLOYMENT_ID',
        'api_version': 'API_VERSION',
        'api_max_tokens': 'API_MAX_TOKENS',
        'api_temperature': 'API_TEMPERATURE',
        'api_timeout': 'API_TIMEOUT',
        'api_max_retries': 'API_MAX_RETRIES',
        'port': 'PORT'
    }
    
    for key, value in config.items():
        env_var_name = env_mapping.get(key, key.upper())
        env_value = os.getenv(env_var_name)
        
        # Determine source
        if env_value is not None:
            source = "environment_variable"
            env_var = env_var_name
        else:
            source = "default_value"
            env_var = env_var_name
        
        # Apply security masking
        if value is None or value == '':
            masked_value = "NOT_SET"
        elif 'password' in key.lower() or 'key' in key.lower():
            if len(str(value)) > 8:
                masked_value = str(value)[:4] + "***" + str(value)[-4:]
            elif value:
                masked_value = "***"
            else:
                masked_value = "NOT_SET"
        elif 'url' in key.lower() and value and "@" in str(value):
            # Special handling for database URLs with credentials
            url_str = str(value)
            parts = url_str.split("://")
            if len(parts) == 2:
                protocol = parts[0]
                rest = parts[1]  
                if "@" in rest:
                    auth_part, host_part = rest.split("@", 1)
                    if ":" in auth_part:
                        user, _ = auth_part.split(":", 1)
                        masked_value = f"{protocol}://{user}:***@{host_part}"
                    else:
                        masked_value = f"{protocol}://{auth_part}:***@{host_part}"
                else:
                    masked_value = value
            else:
                masked_value = value
        else:
            masked_value = value
            
        config_with_sources[key] = {
            "value": masked_value,
            "source": source,
            "env_var": env_var
        }

    return jsonify({
        "service": "Database Schema Glossary Generator",
        "version": "v2.1-unified-config-static",
        "configuration": config_with_sources,
        "summary": {
            "total_settings": len(config_with_sources),
            "from_environment": len([c for c in config_with_sources.values() if c["source"] == "environment_variable"]),
            "using_defaults": len([c for c in config_with_sources.values() if c["source"] == "default_value"])
        },
        "setup_help": {
            "required_env_vars": ["DATABASE_URL", "API_BASE_URL", "API_KEY"],
            "optional_env_vars": [
                "DATABASE_SCHEMA", "API_DEPLOYMENT_ID", "API_VERSION",
                "API_MAX_TOKENS", "API_TEMPERATURE", "API_TIMEOUT", 
                "API_MAX_RETRIES", "PORT"
            ],
            "local_development": "Copy .env.example to .env and edit with your values",
            "production": "Set environment variables in your deployment platform"
        },
        "note": "Sensitive data (passwords, API keys) are masked with *** for security"
    })

@app.route('/prompts')
def get_prompt_templates():
    """Get available prompt templates"""
    try:
        prompts = load_prompts()
        if not prompts:
            return jsonify({
                "error": "Failed to load prompt templates",
                "details": "prompts.json file not found or invalid"
            }), 500
        
        # Format for API response
        templates = {}
        for key, value in prompts.items():
            templates[key] = {
                "name": value["name"],
                "description": value["description"]
            }
        
        return jsonify({
            "prompt_templates": templates,
            "available_routes": list(templates.keys()),
            "usage": "Each route automatically uses its corresponding prompt template",
            "count": len(templates)
        })
    except Exception as e:
        logger.error(f"Error getting prompt templates: {e}")
        return jsonify({
            "error": "Failed to retrieve prompt templates",
            "details": str(e)
        }), 500

@app.route('/generate', methods=['POST'])
def generate_output():
    """Transform glossary data directly into CSV format (no AI)."""
    try:
        start_time = time.time()
        
        # Get input data from request body
        request_data = request.get_json()
        if not request_data:
            return jsonify({
                "success": False,
                "error": "Request body is required",
                "details": "Provide JSON data to transform"
            }), 400
        
        # Extract the input data (should be the output from /analyze)
        input_data = request_data.get('data')
        if not input_data:
            return jsonify({
                "success": False,
                "error": "Missing 'data' field",
                "details": "Provide the glossary data to transform in the 'data' field"
            }), 400
        
        logger.info("Starting direct glossary data transformation to CSV...")
        
        # Transform data directly to CSV format
        csv_content = transform_to_csv(input_data)
        
        processing_time = round(time.time() - start_time, 2)
        
        logger.info(f"Direct transformation completed successfully in {processing_time}s")
        
        # Return CSV content with proper headers
        from flask import Response
        return Response(
            csv_content,
            content_type='text/csv',
            headers={'Content-Disposition': 'attachment; filename="glossary_export.csv"'}
        )
            
    except json.JSONDecodeError:
        logger.error("Invalid JSON in request body")
        return jsonify({
            "success": False,
            "error": "Invalid JSON format",
            "details": "Request body must be valid JSON"
        }), 400
    except Exception as e:
        logger.error(f"Error in generate endpoint: {e}")
        return jsonify({
            "success": False,
            "error": "Internal server error",
            "details": str(e)
        }), 500

@app.route('/database/tables')
def list_tables():
    """List all tables in the configured database schema"""
    try:
        engine = get_database_engine()
        if not engine:
            return jsonify({"error": "Database connection not available"}), 503
        
        config = load_config()
        schema_name = config.get('database_schema') if config else None
        
        with engine.connect() as conn:
            inspector = inspect(engine)
            
            if schema_name:
                tables = inspector.get_table_names(schema=schema_name)
                return jsonify({
                    "schema": schema_name,
                    "tables": sorted(tables),
                    "count": len(tables)
                })
            else:
                tables = inspector.get_table_names()
                return jsonify({
                    "schema": "default",
                    "tables": sorted(tables),
                    "count": len(tables)
                })
                
    except Exception as e:
        logger.error(f"Error listing tables: {e}")
        return jsonify({
            "error": "Failed to list tables",
            "details": str(e)
        }), 500

@app.route('/database/schema/<table_name>')
def get_table_schema(table_name):
    """Get schema information for a specific table"""
    try:
        engine = get_database_engine()
        if not engine:
            return jsonify({"error": "Database connection not available"}), 503
        
        config = load_config()
        schema_name = config.get('database_schema') if config else None
        
        with engine.connect() as conn:
            inspector = inspect(engine)
            
            # Get columns with proper serialization
            columns = inspector.get_columns(table_name, schema=schema_name)
            serialized_columns = []
            
            for col in columns:
                col_info = {
                    "name": col["name"],
                    "type": str(col["type"]),
                    "nullable": col.get("nullable", True),
                    "default": str(col["default"]) if col.get("default") is not None else None,
                    "comment": col.get("comment")
                }
                serialized_columns.append(col_info)
            
            # Get primary keys
            pk_constraint = inspector.get_pk_constraint(table_name, schema=schema_name)
            
            # Get foreign keys with proper serialization
            foreign_keys = inspector.get_foreign_keys(table_name, schema=schema_name)
            serialized_fks = []
            
            for fk in foreign_keys:
                fk_info = {
                    "name": fk.get("name"),
                    "constrained_columns": fk.get("constrained_columns", []),
                    "referred_table": fk.get("referred_table"),
                    "referred_columns": fk.get("referred_columns", []),
                    "referred_schema": fk.get("referred_schema")
                }
                serialized_fks.append(fk_info)
            
            # Get indexes with proper serialization
            indexes = inspector.get_indexes(table_name, schema=schema_name)
            serialized_indexes = []
            
            for idx in indexes:
                idx_info = {
                    "name": idx.get("name"),
                    "column_names": idx.get("column_names", []),
                    "unique": idx.get("unique", False)
                }
                serialized_indexes.append(idx_info)
            
            return jsonify({
                "table_name": table_name,
                "schema": schema_name or "default",
                "columns": serialized_columns,
                "primary_keys": pk_constraint.get('constrained_columns', []),
                "foreign_keys": serialized_fks,
                "indexes": serialized_indexes,
                "column_count": len(serialized_columns)
            })
            
    except Exception as e:
        logger.error(f"Error getting table schema for {table_name}: {e}")
        return jsonify({
            "error": f"Failed to get schema for table '{table_name}'",
            "details": str(e)
        }), 500

@app.route('/analyze', methods=['POST'])
def analyze_schema():
    """Main endpoint to analyze database schema and generate AI-powered business glossary."""
    try:
        start_time = time.time()
        
        # Get configuration from request body (optional)
        request_data = request.get_json() or {}
        
        logger.info("Starting database schema analysis for glossary generation...")
        
        # Check if database configuration is provided in request
        request_db_config = request_data.get('database', {})
        if request_db_config:
            # Use database config from request
            db_url = request_db_config.get('url')
            schema_name = request_db_config.get('schema')
            
            if not db_url:
                return jsonify({
                    "success": False,
                    "error": "Database URL is required when providing database configuration",
                    "details": "Include 'url' in the database configuration object"
                }), 400
            
            # Create engine with request database config
            try:
                logger.info(f"Using database configuration from request")
                engine = create_engine(
                    db_url,
                    pool_timeout=10,
                    pool_recycle=3600,
                    pool_pre_ping=True,
                    connect_args={"connect_timeout": 10}
                )
                
                # Test the connection
                with engine.connect() as conn:
                    conn.execute(text("SELECT 1"))
                logger.info("Database connection from request config established successfully")
                
            except Exception as e:
                logger.error(f"Database connection failed with request config: {e}")
                return jsonify({
                    "success": False,
                    "error": "Database connection failed",
                    "details": f"Could not connect to database with provided configuration: {str(e)}"
                }), 503
        else:
            # Use default database engine
            engine = get_database_engine()
            if not engine:
                return jsonify({
                    "success": False,
                    "error": "Database connection not available",
                    "details": "Could not establish database connection. Check your DATABASE_URL configuration or provide database config in request."
                }), 503
            
            # Get schema name from default config
            config = load_config()
            schema_name = config.get('database_schema') if config else None
        
        # Create schema summary for API call
        schema_summary = create_schema_summary(engine, schema_name)
        logger.info("Schema summary created for AI analysis")
        
        # Extract API configuration from request or use defaults
        api_config = request_data.get('api', {}) if request_data else {}
        
        # Use route-based prompt template (analyze endpoint uses "analyze" prompt)
        prompt_template_name = 'analyze'
        
        # Make API call with schema summary
        api_response = make_api_call(schema_summary, api_config if api_config else None, prompt_template_name)
        
        processing_time = round(time.time() - start_time, 2)
        
        # Get table count for metadata
        with engine.connect() as conn:
            inspector = inspect(engine)
            if schema_name:
                tables = inspector.get_table_names(schema=schema_name)
            else:
                tables = inspector.get_table_names()
            table_count = len(tables)
        
        if api_response:
            logger.info("AI-powered glossary generation completed successfully")
            return jsonify({
                "success": True,
                "data": api_response,
                "metadata": {
                    "tables_analyzed": table_count,
                    "schema_name": schema_name or "default",
                    "processing_time": processing_time,
                    "ai_model_used": api_config.get('model', 'model-router') if api_config else 'model-router',
                    "database_source": "request_override" if request_db_config else "environment_config"
                }
            })
        else:
            return jsonify({
                "success": False,
                "error": "AI analysis failed after all retry attempts",
                "details": "The AI service could not generate a valid glossary. Check your API configuration and try again.",
                "metadata": {
                    "tables_analyzed": table_count,
                    "schema_name": schema_name or "default",
                    "processing_time": processing_time
                }
            }), 500
            
    except Exception as e:
        logger.error(f"Error in analyze_schema: {e}")
        return jsonify({
            "success": False,
            "error": "Internal server error during analysis",
            "details": str(e)
        }), 500

@app.route('/docs', methods=['GET'])
def documentation():
    """API documentation endpoint - loads from external HTML file."""
    try:
        config = load_config()
        
        # Get actual default values from configuration
        masked_db_url = "NOT_CONFIGURED"
        masked_api_key = "NOT_CONFIGURED"
        default_base_url = "NOT_CONFIGURED"
        default_schema = "public"
        
        if config:
            db_url = config.get('database_url', '')
            if db_url and "@" in db_url:
                parts = db_url.split("://")
                if len(parts) == 2:
                    protocol = parts[0]
                    rest = parts[1]  
                    if "@" in rest:
                        auth_part, host_part = rest.split("@", 1)
                        if ":" in auth_part:
                            user, _ = auth_part.split(":", 1)
                            masked_db_url = f"{protocol}://{user}:***@{host_part}"
            else:
                masked_db_url = db_url if db_url else "NOT_CONFIGURED"
            
            api_key = config.get('api_key', '')
            if len(api_key) > 8:
                masked_api_key = api_key[:4] + "***" + api_key[-4:]
            elif api_key:
                masked_api_key = "***"
            else:
                masked_api_key = "NOT_CONFIGURED"
            
            default_base_url = config.get('api_base_url', '') or "NOT_CONFIGURED"
            default_schema = config.get('database_schema', '') or "public"
        
        # Load documentation template from external file
        docs_file_path = os.path.join(os.path.dirname(__file__), 'docs', 'api-docs.html')
        
        if os.path.exists(docs_file_path):
            with open(docs_file_path, 'r', encoding='utf-8') as f:
                docs_html = f.read()
            
            # Replace placeholders with actual configuration values
            docs_html = docs_html.replace('{{masked_db_url}}', masked_db_url)
            docs_html = docs_html.replace('{{masked_api_key}}', masked_api_key)
            docs_html = docs_html.replace('{{default_base_url}}', default_base_url)
            docs_html = docs_html.replace('{{default_schema}}', default_schema)
            
            return docs_html
        else:
            # Fallback simple documentation if file not found
            return f"""
            <html><body>
            <h1>API Documentation</h1>
            <p>Documentation file not found. Please ensure docs/api-docs.html exists.</p>
            <p>Current config: DB={masked_db_url}, API={default_base_url}</p>
            <h3>Available Endpoints:</h3>
            <ul>
                <li>POST /analyze - Analyze database schema</li>
                <li>POST /generate - Generate CSV from hierarchical data</li>
                <li>GET /health - Health check</li>
                <li>GET /config - View configuration</li>
                <li>GET /database/tables - List database tables</li>
            </ul>
            </body></html>
            """
    except Exception as e:
        logger.error(f"Error loading documentation: {e}")
        return jsonify({
            "success": False,
            "error": "Error loading documentation",
            "details": str(e)
        }), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
