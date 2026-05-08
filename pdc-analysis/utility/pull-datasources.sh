#!/bin/bash

################################################################################
# pull-datasources.sh
#
# Downloads Pentaho data sources (Analysis, DSW, Metadata, JDBC) via Data Access
# REST API and optionally uncompresses ZIP exports.
#
# Usage:
#   ./pull-datasources.sh [--uncompress] <output-dir> <server-ip> [username] [password]
#
# Parameters:
#   --uncompress : Extract ZIP exports after downloading (optional)
#   output-dir   : Directory to save exports
#   server-ip    : Pentaho server host or host:port
#   username     : Pentaho username (optional, defaults to 'admin')
#   password     : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./pull-datasources.sh ./ds-exports 10.80.230.193:80
#   ./pull-datasources.sh --uncompress ./ds-exports 10.80.230.193:80 admin password
#
# Requirements:
#   - curl command must be available
#   - unzip required only if --uncompress is used
#
# Optional environment overrides for curl behavior:
#   CURL_CONNECT_TIMEOUT (default: 10)
#   CURL_SPEED_LIMIT (bytes/sec, default: 1024)
#   CURL_SPEED_TIME (seconds, default: 30)
#   CURL_MAX_TIME (seconds, default: 0 = no limit)
#   CURL_RETRY (default: 3)
#   CURL_RETRY_DELAY (default: 2)
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
info() { echo -e "${YELLOW}INFO: $1${NC}"; }

# Curl behavior (override via env vars)
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-10}"
CURL_SPEED_LIMIT="${CURL_SPEED_LIMIT:-1024}"
CURL_SPEED_TIME="${CURL_SPEED_TIME:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-0}"
CURL_RETRY="${CURL_RETRY:-3}"
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-2}"

CURL_BIN="/usr/bin/curl"
if [ ! -x "$CURL_BIN" ]; then
    CURL_BIN="curl"
fi

# Check if curl is available
if ! command -v "$CURL_BIN" &> /dev/null; then
    error "curl command not found. Please install curl."
    exit 1
fi

# Parse flags
UNCOMPRESS="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uncompress)
            UNCOMPRESS="yes"
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Validate parameters
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [--uncompress] <output-dir> <server-ip> [username] [password]"
    exit 1
fi

OUTPUT_DIR="$1"
SERVER_IP="$2"
USERNAME="${3:-admin}"
PASSWORD="${4:-password}"

# Strip quotes if present
SERVER_IP="${SERVER_IP%\"}"
SERVER_IP="${SERVER_IP#\"}"
OUTPUT_DIR="${OUTPUT_DIR%\"}"
OUTPUT_DIR="${OUTPUT_DIR#\"}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR" || {
    error "Unable to create output directory: $OUTPUT_DIR"
    exit 1
}

if [ ! -w "$OUTPUT_DIR" ]; then
    error "Output directory not writable: $OUTPUT_DIR"
    exit 1
fi

# Construct Pentaho server URL (support host:port)
if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

DATA_ACCESS_URL="${PENTAHO_URL}/plugin/data-access/api/datasource"
ANALYSIS_LIST_URL="${DATA_ACCESS_URL}/analysis/catalog"
DSW_LIST_URL="${DATA_ACCESS_URL}/dsw/domain"
METADATA_LIST_URL="${DATA_ACCESS_URL}/metadata/domain"
JDBC_LIST_URL="${DATA_ACCESS_URL}/jdbc/connection"

ANALYSIS_DIR="${OUTPUT_DIR}/analysis"
DSW_DIR="${OUTPUT_DIR}/dsw"
METADATA_DIR="${OUTPUT_DIR}/metadata"
JDBC_DIR="${OUTPUT_DIR}/jdbc"

mkdir -p "$ANALYSIS_DIR" "$DSW_DIR" "$METADATA_DIR" "$JDBC_DIR"

build_curl_opts() {
    CURL_OPTS=(
        --user "${USERNAME}:${PASSWORD}"
        --location
        --show-error
        --progress-bar
        --connect-timeout "$CURL_CONNECT_TIMEOUT"
        --retry "$CURL_RETRY"
        --retry-delay "$CURL_RETRY_DELAY"
        --speed-limit "$CURL_SPEED_LIMIT"
        --speed-time "$CURL_SPEED_TIME"
    )
    if [ "$CURL_MAX_TIME" -gt 0 ]; then
        CURL_OPTS+=(--max-time "$CURL_MAX_TIME")
    fi
}

url_encode() {
    echo -n "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

fetch_list() {
    local url="$1"
    local tmp_file
    tmp_file=$(mktemp)
    local code
    code=$($CURL_BIN -s -w "%{http_code}" -o "$tmp_file" \
        "${CURL_OPTS[@]}" \
        -H "Accept: application/xml, application/json" \
        "$url")
    if [ "$code" -ne 200 ]; then
        rm -f "$tmp_file"
        error "List request failed ($code): $url"
        return 1
    fi
    /usr/bin/perl -0777 -ne '
        my $t = $_;
        if ($t =~ /<Item/i) {
            while ($t =~ /<Item[^>]*>([^<]*)</g) { print "$1\n" if length $1; }
            exit 0;
        }
        if ($t =~ /"\$"\s*:\s*"/s) {
            while ($t =~ /"\$"\s*:\s*"([^"]*)"/g) { print "$1\n" if length $1; }
            exit 0;
        }
        if ($t =~ /"Item"\s*:\s*\[/s) {
            if ($t =~ /"Item"\s*:\s*\[(.*?)\]/s) {
                my $arr = $1;
                while ($arr =~ /"([^"]*)"/g) { print "$1\n" if length $1; }
            }
        }
    ' "$tmp_file"
    rm -f "$tmp_file"
}

download_to_file() {
    local url="$1"
    local out_file="$2"
    local code
    code=$($CURL_BIN -s -w "%{http_code}" -o "$out_file" \
        "${CURL_OPTS[@]}" \
        "$url")
    if [ "$code" -ne 200 ]; then
        error "Download failed ($code): $url"
        rm -f "$out_file"
        return 1
    fi
    return 0
}

handle_zip_or_xmi() {
    local url="$1"
    local base_path="$2"
    local tmp_file
    tmp_file=$(mktemp)
    local code
    code=$($CURL_BIN -s -w "%{http_code}" -o "$tmp_file" \
        "${CURL_OPTS[@]}" \
        "$url")
    if [ "$code" -ne 200 ]; then
        rm -f "$tmp_file"
        error "Download failed ($code): $url"
        return 1
    fi

    local header
    header=$(/usr/bin/xxd -p -l 2 "$tmp_file" | /usr/bin/tr -d '\n')
    if [ "$header" = "504b" ]; then
        local zip_file="${base_path}.zip"
        mv "$tmp_file" "$zip_file"
        if [ "$UNCOMPRESS" = "yes" ] || [ "$UNCOMPRESS" = "true" ]; then
            if ! command -v unzip &> /dev/null; then
                error "unzip command not found. Install unzip or rerun with uncompress=no."
                return 1
            fi
            info "Uncompressing $zip_file..."
            unzip -o "$zip_file" -d "$(dirname "$base_path")" >/dev/null
            rm -f "$zip_file"
            info "Removed archive: $zip_file"
        fi
    else
        local xmi_file="${base_path}.xmi"
        mv "$tmp_file" "$xmi_file"
    fi
}

build_curl_opts

info "Starting data source export..."
info "Output: $OUTPUT_DIR"
info "Server: $PENTAHO_URL"

info "Listing Analysis catalogs..."
analysis_ids=$(fetch_list "$ANALYSIS_LIST_URL" || true)
while IFS= read -r id; do
    [ -z "$id" ] && continue
    encoded_id=$(url_encode "$id")
    safe_name=$(echo -n "$id" | /usr/bin/sed 's#[/\\]#_#g')
    info "Downloading Analysis: $id"
    download_to_file "${ANALYSIS_LIST_URL}/${encoded_id}" "${ANALYSIS_DIR}/${safe_name}.xml" || true
    if [ -f "${ANALYSIS_DIR}/${safe_name}.xml" ]; then
        success "Saved ${ANALYSIS_DIR}/${safe_name}.xml"
    fi
    sleep 0.1
done <<< "$analysis_ids"

info "Listing DSW domains..."
dsw_ids=$(fetch_list "$DSW_LIST_URL" || true)
while IFS= read -r id; do
    [ -z "$id" ] && continue
    encoded_id=$(url_encode "$id")
    safe_name=$(echo -n "$id" | /usr/bin/sed 's#[/\\]#_#g')
    info "Downloading DSW: $id"
    handle_zip_or_xmi "${DSW_LIST_URL}/${encoded_id}" "${DSW_DIR}/${safe_name}" || true
    sleep 0.1
done <<< "$dsw_ids"

info "Listing Metadata domains..."
metadata_ids=$(fetch_list "$METADATA_LIST_URL" || true)
while IFS= read -r id; do
    [ -z "$id" ] && continue
    encoded_id=$(url_encode "$id")
    safe_name=$(echo -n "$id" | /usr/bin/sed 's#[/\\]#_#g')
    info "Downloading Metadata: $id"
    handle_zip_or_xmi "${METADATA_LIST_URL}/${encoded_id}" "${METADATA_DIR}/${safe_name}" || true
    sleep 0.1
done <<< "$metadata_ids"

info "Listing JDBC connections..."
jdbc_ids=$(fetch_list "$JDBC_LIST_URL" || true)
while IFS= read -r id; do
    [ -z "$id" ] && continue
    encoded_id=$(url_encode "$id")
    safe_name=$(echo -n "$id" | /usr/bin/sed 's#[/\\]#_#g')
    info "Downloading JDBC: $id"
    download_to_file "${JDBC_LIST_URL}/${encoded_id}" "${JDBC_DIR}/${safe_name}.json" || true
    if [ -f "${JDBC_DIR}/${safe_name}.json" ]; then
        success "Saved ${JDBC_DIR}/${safe_name}.json"
    fi
    sleep 0.1
done <<< "$jdbc_ids"

success "Data source export complete."
