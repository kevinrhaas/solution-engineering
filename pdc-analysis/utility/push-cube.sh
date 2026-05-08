#!/bin/bash

################################################################################
# push-cube.sh  (formerly publish-analyzer-cube.sh)
#
# Publishes an analyzer cube (Mondrian schema) to Pentaho Server using the 
# Data Source Analysis Resource REST API
#
# API Endpoint: PUT /plugin/data-access/api/datasource/analysis/catalog/{catalogId}
# Documentation: https://docs.pentaho.com/rest-api/data-source-apis-analysis-resource
#
# Note: The cube/schema name is read from the XML file's <Schema name="..."> attribute.
#       The catalogId is derived from the datasource name.
#
# Usage:
#   ./push-cube.sh <xml-file> <datasource-name> <server-ip[:port]> [username] [password]
#
# Parameters:
#   xml-file        : Path to the Mondrian schema XML file
#   datasource-name : Name of the datasource to publish to
#   server-ip[:port]: Pentaho server IP/hostname, optionally with :port (defaults to :8000)
#   username        : Pentaho username (optional, defaults to 'admin')
#   password        : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./push-cube.sh sales_cube.xml SampleData 192.168.1.100
#   ./push-cube.sh sales_cube.xml SampleData 192.168.1.100:8000
#   ./push-cube.sh pdso_entities.xml SteelWheels localhost:8080 admin mypassword
#
# Note: This script publishes cubes using the Pentaho Analyzer API.
#       For general file uploads to repository, use upload.sh instead.
#
# Requirements:
#   - curl command must be available
#   - Valid Pentaho server credentials
#   - Network access to Pentaho server
#   - Pentaho Analyzer plugin installed on server
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print error messages
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Function to print success messages
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to print info messages
info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Check if curl is available
if ! command -v curl &> /dev/null; then
    error "curl command not found. Please install curl."
    exit 1
fi

# Validate parameters
if [ $# -lt 3 ] || [ $# -gt 5 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 <xml-file> <datasource-name> <server-ip[:port]> [username] [password]"
    echo ""
    echo "Parameters:"
    echo "  xml-file        : Path to the Mondrian schema XML file"
    echo "  datasource-name : Name of the datasource to publish to"
    echo "  server-ip[:port]: Pentaho server IP/hostname, optionally with :port (defaults to :8000)"
    echo "  username        : Pentaho username (optional, defaults to 'admin')"
    echo "  password        : Pentaho password (optional, defaults to 'password')"
    echo ""
    echo "Examples:"
    echo "  $0 sales_cube.xml SampleData 192.168.1.100"
    echo "  $0 sales_cube.xml SampleData 192.168.1.100:8000"
    echo "  $0 pdso_entities.xml SteelWheels localhost:8080 admin mypassword"
    exit 1
fi

# Parse parameters
XML_FILE="$1"
DATASOURCE_NAME="$2"
SERVER_ADDRESS="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

# Strip quotes if present (handles Pentaho parameter edge cases)
XML_FILE="${XML_FILE%\"}"
XML_FILE="${XML_FILE#\"}"
DATASOURCE_NAME="${DATASOURCE_NAME%\"}"
DATASOURCE_NAME="${DATASOURCE_NAME#\"}"
SERVER_ADDRESS="${SERVER_ADDRESS%\"}"
SERVER_ADDRESS="${SERVER_ADDRESS#\"}"

# Parse server address to extract IP/hostname and port
if [[ "$SERVER_ADDRESS" =~ : ]]; then
    # Port specified in address (e.g., "10.80.230.166:8000")
    SERVER_IP="${SERVER_ADDRESS%%:*}"
    SERVER_PORT="${SERVER_ADDRESS##*:}"
else
    # No port specified, use default
    SERVER_IP="$SERVER_ADDRESS"
    SERVER_PORT="8000"
fi

# Validate XML file exists
if [ ! -f "$XML_FILE" ]; then
    error "File not found: $XML_FILE"
    exit 1
fi

# Validate XML file is readable
if [ ! -r "$XML_FILE" ]; then
    error "File not readable: $XML_FILE"
    exit 1
fi

# Read XML content
XML_CONTENT=$(cat "$XML_FILE")

# Get filename without extension for schemaFileInfo
FILENAME=$(basename "$XML_FILE")
SCHEMA_FILE_INFO="${FILENAME%.*}"

# Use filename (without extension) as the catalog ID
CATALOG_ID="${SCHEMA_FILE_INFO}"

# Construct Pentaho server URL
PENTAHO_URL="http://${SERVER_IP}:${SERVER_PORT}/pentaho"

info "Publishing analyzer cube..."
info "File: $XML_FILE"
info "Datasource Name: $DATASOURCE_NAME"
info "Catalog ID: $CATALOG_ID"
info "Schema File Info: $SCHEMA_FILE_INFO"
info "Server: $PENTAHO_URL"

# Construct the analyzer publish URL
# The analyzer API typically uses: /plugin/analyzer/api/cube/update or /plugin/analyzer/api/cube/create
PUBLISH_URL="${PENTAHO_URL}/plugin/analyzer/api/cube/create"

# Create temporary files for response
RESPONSE_FILE=$(mktemp)
HTTP_CODE_FILE=$(mktemp)

# Cleanup temp files on exit
trap "rm -f $RESPONSE_FILE $HTTP_CODE_FILE" EXIT

info "Sending publish request to Pentaho Analyzer API..."

# Use the correct Analysis Resource API endpoint
# PUT /plugin/data-access/api/datasource/analysis/catalog/{catalogId}
PUBLISH_URL="${PENTAHO_URL}/plugin/data-access/api/datasource/analysis/catalog/${CATALOG_ID}"

# First, test basic connectivity
info "Testing server connectivity..."
PING_TEST=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --user "${USERNAME}:${PASSWORD}" "${PENTAHO_URL}/api/version" 2>&1)
if [ "$PING_TEST" = "000" ] || [ -z "$PING_TEST" ]; then
    error "Cannot connect to Pentaho server at: $PENTAHO_URL"
    echo ""
    info "Troubleshooting steps:"
    info "1. Verify the server IP/hostname is correct: $SERVER_IP:$SERVER_PORT"
    info "2. Check if Pentaho is running: curl http://${SERVER_IP}:${SERVER_PORT}/pentaho"
    info "3. Verify port $SERVER_PORT is accessible (firewall, network, etc.)"
    info "4. Test with: curl -u ${USERNAME}:password http://${SERVER_IP}:${SERVER_PORT}/pentaho/api/version"
    exit 1
fi
info "Server is reachable (HTTP $PING_TEST)"

# Now attempt the publish
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
    --connect-timeout 30 \
    --max-time 120 \
    --user "${USERNAME}:${PASSWORD}" \
    -X PUT \
    -H "Content-Type: multipart/form-data" \
    -F "uploadInput=@${XML_FILE}" \
    -F "schemaFileInfo=${SCHEMA_FILE_INFO}" \
    -F "datasourceName=${DATASOURCE_NAME}" \
    -F "overwrite=true" \
    -F "xmlaEnabledFlag=true" \
    -F "parameters=Datasource=${DATASOURCE_NAME}" \
    "${PUBLISH_URL}" 2>&1)

echo "$HTTP_CODE" > "$HTTP_CODE_FILE"

# Check response
if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
    success "Analyzer cube published successfully!"
    success "Datasource: $DATASOURCE_NAME"
    success "Catalog ID: $CATALOG_ID"
    echo ""
    
    # Refresh Mondrian schema cache
    info "Refreshing Mondrian schema cache..."
    CACHE_REFRESH_URL="${PENTAHO_URL}/api/system/refresh/mondrianSchemaCache"
    
    CACHE_HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
        --connect-timeout 10 \
        --max-time 30 \
        --user "${USERNAME}:${PASSWORD}" \
        -X GET \
        "${CACHE_REFRESH_URL}")
    
    if [ "$CACHE_HTTP_CODE" -eq 200 ] || [ "$CACHE_HTTP_CODE" -eq 204 ]; then
        success "Mondrian cache refreshed successfully!"
    else
        error "Warning: Cache refresh failed with HTTP status: $CACHE_HTTP_CODE"
        info "Trying alternative endpoint..."
        
        # Try alternative endpoint
        ALT_CACHE_URL="${PENTAHO_URL}/plugin/data-access/api/datasource/analysis/refreshSchemaCache"
        ALT_HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
            --connect-timeout 10 \
            --max-time 30 \
            --user "${USERNAME}:${PASSWORD}" \
            -X GET \
            "${ALT_CACHE_URL}")
        
        if [ "$ALT_HTTP_CODE" -eq 200 ] || [ "$ALT_HTTP_CODE" -eq 204 ]; then
            success "Mondrian cache refreshed successfully (alternative endpoint)!"
        else
            error "Cache refresh failed on both endpoints (${CACHE_HTTP_CODE}, ${ALT_HTTP_CODE})"
            info "You may need to manually refresh the cache in Pentaho User Console."
            info "Tools > Refresh > Mondrian Schema Cache"
        fi
    fi
    
    echo ""
    info "The cube should now be available in Pentaho Analyzer."
    info "Schema name is defined in the XML file's <Schema name=\"...\"> attribute."
    exit 0
elif [ "$HTTP_CODE" -eq 401 ]; then
    error "Authentication failed. Please check username and password."
    error "HTTP Status: $HTTP_CODE"
    exit 1
elif [ "$HTTP_CODE" -eq 403 ]; then
    error "Access denied. User '$USERNAME' does not have permission to publish cubes."
    error "HTTP Status: $HTTP_CODE"
    exit 1
elif [ "$HTTP_CODE" -eq 404 ]; then
    error "Analyzer API endpoint not found."
    error "HTTP Status: $HTTP_CODE"
    echo ""
    info "Possible causes:"
    info "1. Pentaho Analyzer plugin is not installed or not enabled"
    info "2. Server URL is incorrect: $PENTAHO_URL"
    info "3. Check that the data-access plugin is available"
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    exit 1
elif [ "$HTTP_CODE" -eq 409 ]; then
    error "Cube already exists. The 'overwrite=true' flag should have replaced it."
    error "HTTP Status: $HTTP_CODE"
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    exit 1
elif [ "$HTTP_CODE" -eq 500 ]; then
    error "Server error occurred during publish."
    error "HTTP Status: $HTTP_CODE"
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    exit 1
else
    error "Publish failed with HTTP status code: $HTTP_CODE"
    if [ "$HTTP_CODE" = "000" ]; then
        echo ""
        error "Connection failed - could not reach the server."
        info "This usually means:"
        info "  - Server is not running or not accessible"
        info "  - Network/firewall blocking the connection"
        info "  - Wrong server IP or port"
        info "  - SSL/TLS issues (try https:// instead of http:// if needed)"
    fi
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    echo ""
    info "For manual publishing, consider using:"
    info "1. Pentaho User Console (PUC) web interface"
    info "2. Or upload using: ./upload.sh $XML_FILE /public/analyzer ${SERVER_IP}:${SERVER_PORT}"
    exit 1
fi
