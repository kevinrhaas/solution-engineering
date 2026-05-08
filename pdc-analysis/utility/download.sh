#!/bin/bash

################################################################################
# download.sh
#
# Downloads a single file or folder from Pentaho Server repository to a local
# path. Counterpart to upload.sh.
#
# For smart delta-sync of an entire directory, use pull-content.sh instead.
#
# Usage:
#   ./download.sh [--dry-run] <repo-path> <local-path> <server-ip> [username] [password]
#
# Parameters:
#   --dry-run   : Show what would be downloaded without writing files
#   repo-path   : Repository path to download (e.g., /public/pdc-analysis/utility/main/j-main-script.kjb)
#   local-path  : Local file or directory to write to
#   server-ip   : Pentaho server host or host:port
#   username    : Pentaho username (optional, defaults to 'admin')
#   password    : Pentaho password (optional, defaults to 'password')
#
# Behavior:
#   - If repo-path points to a file: downloads the single file to local-path
#   - If repo-path points to a folder: downloads as zip archvie and extracts to local-path
#
# Examples:
#   # Download a single file
#   ./download.sh /public/pdc-analysis/utility/main/j-main-script.kjb ./j-main-script.kjb 10.80.230.193:80
#
#   # Download a folder
#   ./download.sh /public/pdc-analysis ./content/public/pdc-analysis 10.80.230.193:80
#
#   # Dry run
#   ./download.sh --dry-run /public/pdc-analysis ./local-copy 10.80.230.193:80
#
# Requirements:
#   - curl, unzip (unzip only needed for folder downloads)
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
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
if [ $# -lt 3 ] || [ $# -gt 5 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [--dry-run] <repo-path> <local-path> <server-ip> [username] [password]"
    echo ""
    echo "Parameters:"
    echo "  --dry-run   : Show what would happen without writing files"
    echo "  repo-path   : Repository path to download"
    echo "  local-path  : Local file or directory to write to"
    echo "  server-ip   : Pentaho server host or host:port"
    echo "  username    : Pentaho username (optional, defaults to 'admin')"
    echo "  password    : Pentaho password (optional, defaults to 'password')"
    echo ""
    echo "Examples:"
    echo "  $0 /public/pdc-analysis/utility/main/j-main-script.kjb ./j-main-script.kjb 10.80.230.193:80"
    echo "  $0 /public/pdc-analysis ./content/public/pdc-analysis 10.80.230.193:80"
    echo "  $0 --dry-run /public/pdc-analysis ./local-copy 10.80.230.193:80"
    exit 1
fi

REPO_PATH="$1"
LOCAL_PATH="$2"
SERVER_IP="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

# Strip quotes if present
REPO_PATH="${REPO_PATH%\"}"
REPO_PATH="${REPO_PATH#\"}"
LOCAL_PATH="${LOCAL_PATH%\"}"
LOCAL_PATH="${LOCAL_PATH#\"}"
SERVER_IP="${SERVER_IP%\"}"
SERVER_IP="${SERVER_IP#\"}"

# Ensure repo path starts with /
if [[ ! "$REPO_PATH" =~ ^/ ]]; then
    REPO_PATH="/$REPO_PATH"
fi

# Remove trailing slash from repo path
REPO_PATH="${REPO_PATH%/}"

# Construct Pentaho server URL (support host:port)
if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

REPO_FILES_URL="${PENTAHO_URL}/api/repo/files"

# URL helpers (shared with upload.sh conventions)
url_encode() {
    /usr/bin/printf "%s" "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

build_path_id() {
    local path="$1"
    path="${path#/}"
    if [ -z "$path" ]; then
        echo ":"
    else
        echo ":${path//\//:}"
    fi
}

if [ "$DRY_RUN" = "true" ]; then
    info "[DRY RUN] Would download: $REPO_PATH → $LOCAL_PATH"
    info "[DRY RUN] Server: $PENTAHO_URL"
    exit 0
fi

info "Downloading from Pentaho Server..."
info "Source: $REPO_PATH"
info "Target: $LOCAL_PATH"
info "Server: $PENTAHO_URL"

# Build the pathId and download URL
PATH_ID=$(build_path_id "$REPO_PATH")
ENCODED_PATH_ID=$(url_encode "$PATH_ID")
DOWNLOAD_URL="${REPO_FILES_URL}/${ENCODED_PATH_ID}/download"

# Create temporary file for the download
TMP_FILE=$(mktemp)
trap "rm -f '$TMP_FILE'" EXIT

# Download
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TMP_FILE" \
    --connect-timeout 30 \
    --max-time 300 \
    --user "${USERNAME}:${PASSWORD}" \
    "$DOWNLOAD_URL" 2>&1)

if [ "$HTTP_CODE" -eq 404 ]; then
    error "Repository path not found: $REPO_PATH"
    exit 1
elif [ "$HTTP_CODE" -ne 200 ]; then
    error "Download failed (HTTP $HTTP_CODE) for: $REPO_PATH"
    exit 1
fi

# Determine if the download is a zip (folder) or raw file
HEADER=$(/usr/bin/xxd -p -l 2 "$TMP_FILE" | /usr/bin/tr -d '\n')

if [ "$HEADER" = "504b" ]; then
    # ZIP archive — this is a folder download
    if ! command -v unzip &> /dev/null; then
        error "unzip command not found. Required for folder downloads."
        exit 1
    fi

    info "Downloaded zip archive (folder export) — extracting..."

    # Create local directory
    mkdir -p "$LOCAL_PATH"

    # Extract to temp dir first, then find the content root
    EXTRACT_DIR=$(mktemp -d)
    trap "rm -f '$TMP_FILE'; rm -rf '$EXTRACT_DIR'" EXIT

    unzip -q -o "$TMP_FILE" -d "$EXTRACT_DIR"

    # Find the content root (skip exportManifest.xml)
    # Pentaho zips have structure like: public/pdc-analysis/...
    # We need to find the top directory that matches the repo path
    REPO_BASENAME=$(basename "$REPO_PATH")
    CONTENT_ROOT=""

    # Look for the matching directory in the extracted content
    while IFS= read -r dir; do
        base=$(basename "$dir")
        if [ "$base" = "$REPO_BASENAME" ]; then
            CONTENT_ROOT="$dir"
            break
        fi
    done < <(find "$EXTRACT_DIR" -type d -name "$REPO_BASENAME" 2>/dev/null | head -5)

    if [ -z "$CONTENT_ROOT" ]; then
        # Fallback: use everything except exportManifest.xml
        CONTENT_ROOT="$EXTRACT_DIR"
    fi

    # Copy content to local path
    FILE_COUNT=0
    while IFS= read -r -d '' file; do
        rel_path="${file#"$CONTENT_ROOT"/}"
        dest="${LOCAL_PATH}/${rel_path}"
        mkdir -p "$(dirname "$dest")"
        cp "$file" "$dest"
        ((FILE_COUNT++))
    done < <(find "$CONTENT_ROOT" -type f ! -name "exportManifest.xml" -print0)

    success "Downloaded $FILE_COUNT files to $LOCAL_PATH"
else
    # Raw file download
    mkdir -p "$(dirname "$LOCAL_PATH")"
    cp "$TMP_FILE" "$LOCAL_PATH"
    FILE_SIZE=$(wc -c < "$LOCAL_PATH" | tr -d ' ')
    success "Downloaded $LOCAL_PATH ($FILE_SIZE bytes)"
fi
