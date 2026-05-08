#!/bin/bash

################################################################################
# push-datasources.sh
#
# Imports Pentaho data sources (Analysis, DSW, Metadata, JDBC) back to server
# via the Data Access REST API. Counterpart to pull-datasources.sh.
#
# Reads files from the same directory layout that pull-datasources.sh creates:
#   analysis/  → Mondrian XML schemas
#   dsw/       → Data Source Wizard .xmi or .zip files
#   metadata/  → Metadata .xmi or .zip files
#   jdbc/      → JDBC connection .json files
#
# Usage:
#   ./push-datasources.sh [--dry-run] <input-dir> <server-ip> [username] [password]
#
# Parameters:
#   --dry-run   : Show what would be imported without making changes
#   input-dir   : Directory containing datasource files (with analysis/, dsw/, metadata/, jdbc/ subdirs)
#   server-ip   : Pentaho server host or host:port
#   username    : Pentaho username (optional, defaults to 'admin')
#   password    : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./push-datasources.sh ./ds-exports 10.80.230.193:80
#   ./push-datasources.sh --dry-run ./ds-exports 10.80.230.193:80 admin password
#
# Requirements:
#   - curl command must be available
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
info()    { echo -e "${YELLOW}INFO: $1${NC}"; }
detail()  { echo -e "${CYAN}  $1${NC}"; }

# Check prerequisites
if ! command -v curl &> /dev/null; then
    error "curl command not found. Please install curl."
    exit 1
fi

# Parse flags
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Validate positional parameters
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [--dry-run] <input-dir> <server-ip> [username] [password]"
    echo ""
    echo "Parameters:"
    echo "  --dry-run   : Show what would be imported without making changes"
    echo "  input-dir   : Directory with analysis/, dsw/, metadata/, jdbc/ subdirs"
    echo "  server-ip   : Pentaho server host or host:port"
    echo "  username    : Pentaho username (optional, defaults to 'admin')"
    echo "  password    : Pentaho password (optional, defaults to 'password')"
    echo ""
    echo "Examples:"
    echo "  $0 ./ds-exports 10.80.230.193:80"
    echo "  $0 --dry-run ./ds-exports 10.80.230.193:80 admin password"
    exit 1
fi

INPUT_DIR="$1"
SERVER_IP="$2"
USERNAME="${3:-admin}"
PASSWORD="${4:-password}"

# Strip quotes if present
INPUT_DIR="${INPUT_DIR%\"}"
INPUT_DIR="${INPUT_DIR#\"}"
SERVER_IP="${SERVER_IP%\"}"
SERVER_IP="${SERVER_IP#\"}"

# Validate input directory
if [ ! -d "$INPUT_DIR" ]; then
    error "Input directory not found: $INPUT_DIR"
    exit 1
fi

# Construct Pentaho server URL (support host:port)
if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

DATA_ACCESS_URL="${PENTAHO_URL}/plugin/data-access/api/datasource"

url_encode() {
    /usr/bin/printf "%s" "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

# Counters
TOTAL=0
UPLOADED=0
FAILED=0
SKIPPED=0

if [ "$DRY_RUN" = "true" ]; then
    info "[DRY RUN] No changes will be made"
fi
info "Input: $INPUT_DIR"
info "Server: $PENTAHO_URL"
echo ""

# ---------------------------------------------------------------------------
# Analysis catalogs (Mondrian XML schemas)
# PUT /plugin/data-access/api/datasource/analysis/catalog/{catalogId}
# ---------------------------------------------------------------------------
ANALYSIS_DIR="${INPUT_DIR}/analysis"
if [ -d "$ANALYSIS_DIR" ]; then
    info "=== Analysis Catalogs ==="
    while IFS= read -r -d '' xml_file; do
        filename=$(basename "$xml_file")
        catalog_id="${filename%.xml}"
        ((TOTAL++))

        if [ "$DRY_RUN" = "true" ]; then
            detail "[DRY RUN] Would import Analysis: $catalog_id ($filename)"
            ((SKIPPED++))
            continue
        fi

        detail "Importing Analysis: $catalog_id"
        ENCODED_ID=$(url_encode "$catalog_id")
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
            --connect-timeout 30 \
            --max-time 120 \
            --user "${USERNAME}:${PASSWORD}" \
            -X PUT \
            -H "Content-Type: multipart/form-data" \
            -F "uploadInput=@${xml_file}" \
            -F "schemaFileInfo=${catalog_id}" \
            -F "datasourceName=${catalog_id}" \
            -F "overwrite=true" \
            -F "xmlaEnabledFlag=true" \
            -F "parameters=Datasource=${catalog_id}" \
            "${DATA_ACCESS_URL}/analysis/catalog/${ENCODED_ID}" 2>/dev/null)

        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
            success "  Imported Analysis: $catalog_id"
            ((UPLOADED++))
        else
            error "  Failed Analysis: $catalog_id (HTTP $HTTP_CODE)"
            ((FAILED++))
        fi
    done < <(find "$ANALYSIS_DIR" -maxdepth 1 -name "*.xml" -type f -print0 2>/dev/null | sort -z)
    echo ""
else
    info "No analysis/ directory found — skipping Analysis catalogs"
fi

# ---------------------------------------------------------------------------
# DSW domains (Data Source Wizard .xmi or .zip)
# POST /plugin/data-access/api/datasource/dsw/import
# ---------------------------------------------------------------------------
DSW_DIR="${INPUT_DIR}/dsw"
if [ -d "$DSW_DIR" ]; then
    info "=== DSW Domains ==="
    while IFS= read -r -d '' dsw_file; do
        filename=$(basename "$dsw_file")
        # Strip extension (.xmi or .zip)
        domain_id="${filename%.*}"
        ((TOTAL++))

        if [ "$DRY_RUN" = "true" ]; then
            detail "[DRY RUN] Would import DSW: $domain_id ($filename)"
            ((SKIPPED++))
            continue
        fi

        detail "Importing DSW: $domain_id"
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
            --connect-timeout 30 \
            --max-time 120 \
            --user "${USERNAME}:${PASSWORD}" \
            -X POST \
            -H "Content-Type: multipart/form-data" \
            -F "domainId=${domain_id}" \
            -F "fileUpload=@${dsw_file}" \
            -F "overwrite=true" \
            "${DATA_ACCESS_URL}/dsw/import" 2>/dev/null)

        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
            success "  Imported DSW: $domain_id"
            ((UPLOADED++))
        else
            error "  Failed DSW: $domain_id (HTTP $HTTP_CODE)"
            ((FAILED++))
        fi
    done < <(find "$DSW_DIR" -maxdepth 1 \( -name "*.xmi" -o -name "*.zip" \) -type f -print0 2>/dev/null | sort -z)
    echo ""
else
    info "No dsw/ directory found — skipping DSW domains"
fi

# ---------------------------------------------------------------------------
# Metadata domains (.xmi or .zip)
# POST /plugin/data-access/api/datasource/metadata/domain/import
# ---------------------------------------------------------------------------
METADATA_DIR="${INPUT_DIR}/metadata"
if [ -d "$METADATA_DIR" ]; then
    info "=== Metadata Domains ==="
    while IFS= read -r -d '' meta_file; do
        filename=$(basename "$meta_file")
        domain_id="${filename%.*}"
        ((TOTAL++))

        if [ "$DRY_RUN" = "true" ]; then
            detail "[DRY RUN] Would import Metadata: $domain_id ($filename)"
            ((SKIPPED++))
            continue
        fi

        detail "Importing Metadata: $domain_id"
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
            --connect-timeout 30 \
            --max-time 120 \
            --user "${USERNAME}:${PASSWORD}" \
            -X POST \
            -H "Content-Type: multipart/form-data" \
            -F "domainId=${domain_id}" \
            -F "fileUpload=@${meta_file}" \
            -F "overwrite=true" \
            "${DATA_ACCESS_URL}/metadata/domain/import" 2>/dev/null)

        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
            success "  Imported Metadata: $domain_id"
            ((UPLOADED++))
        else
            error "  Failed Metadata: $domain_id (HTTP $HTTP_CODE)"
            ((FAILED++))
        fi
    done < <(find "$METADATA_DIR" -maxdepth 1 \( -name "*.xmi" -o -name "*.zip" \) -type f -print0 2>/dev/null | sort -z)
    echo ""
else
    info "No metadata/ directory found — skipping Metadata domains"
fi

# ---------------------------------------------------------------------------
# JDBC connections (.json)
# PUT /plugin/data-access/api/datasource/jdbc/connection/{connectionName}
# Body: the JSON connection definition
# ---------------------------------------------------------------------------
JDBC_DIR="${INPUT_DIR}/jdbc"
if [ -d "$JDBC_DIR" ]; then
    info "=== JDBC Connections ==="
    while IFS= read -r -d '' json_file; do
        filename=$(basename "$json_file")
        conn_name="${filename%.json}"
        ((TOTAL++))

        if [ "$DRY_RUN" = "true" ]; then
            detail "[DRY RUN] Would import JDBC: $conn_name ($filename)"
            ((SKIPPED++))
            continue
        fi

        detail "Importing JDBC: $conn_name"
        ENCODED_NAME=$(url_encode "$conn_name")
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
            --connect-timeout 30 \
            --max-time 60 \
            --user "${USERNAME}:${PASSWORD}" \
            -X PUT \
            -H "Content-Type: application/json" \
            --data-binary "@${json_file}" \
            "${DATA_ACCESS_URL}/jdbc/connection/${ENCODED_NAME}" 2>/dev/null)

        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
            success "  Imported JDBC: $conn_name"
            ((UPLOADED++))
        else
            error "  Failed JDBC: $conn_name (HTTP $HTTP_CODE)"
            ((FAILED++))
        fi
    done < <(find "$JDBC_DIR" -maxdepth 1 -name "*.json" -type f -print0 2>/dev/null | sort -z)
    echo ""
else
    info "No jdbc/ directory found — skipping JDBC connections"
fi

# Summary
echo "────────────────────────────────────────"
if [ "$DRY_RUN" = "true" ]; then
    echo "DRY RUN SUMMARY"
else
    echo "IMPORT SUMMARY"
fi
echo "  Total:    $TOTAL"
echo "  Uploaded: $UPLOADED"
echo "  Failed:   $FAILED"
echo "  Skipped:  $SKIPPED"
echo "────────────────────────────────────────"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
