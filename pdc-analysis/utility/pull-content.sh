#!/bin/bash

################################################################################
# pull-content.sh
#
# Syncs content from Pentaho Server repository to a local directory.
# Downloads repository content, compares with local files, and intelligently
# merges — keeping backups of locally modified files.
#
# Behavior:
#   - New file (server only):   downloaded to local directory
#   - Identical file:           skipped (no changes)
#   - Changed file (differs):   local copy backed up under archive/content-backup/
#                                preserving relative path, server version replaces original
#
# Usage:
#   ./pull-content.sh [--dry-run] <local-dir> <repo-path> <server-ip> [username] [password]
#
# Parameters:
#   --dry-run   : Show what would happen without making any changes
#   local-dir   : Local directory to sync into
#   repo-path   : Repository path to pull from (e.g., /public/pdc-analysis)
#   server-ip   : Pentaho server host or host:port
#   username    : Pentaho username (optional, defaults to 'admin')
#   password    : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./pull-content.sh ../pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
#   ./pull-content.sh --dry-run ../content /public/pdc-analysis localhost admin mypassword
#   ./pull-content.sh ./local-copy /public/data 10.80.230.193:80 admin password
#
# Requirements:
#   - curl, unzip
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
for cmd in curl unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd command not found. Please install $cmd."
        exit 1
    fi
done

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
    echo "Usage: $0 [--dry-run] <local-dir> <repo-path> <server-ip> [username] [password]"
    echo ""
    echo "Behavior:"
    echo "  - New files (server only):       downloaded to local directory"
    echo "  - Identical files:               skipped"
    echo "  - Changed files (local differs): local backed up as <name>.backup.<timestamp>,"
    echo "                                   server version saved under the original name"
    echo ""
    echo "Examples:"
    echo "  $0 ../pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80"
    echo "  $0 --dry-run ./local-copy /public/data localhost admin mypassword"
    exit 1
fi

LOCAL_DIR="$1"
REPO_PATH="$2"
SERVER_IP="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

# Strip quotes if present
LOCAL_DIR="${LOCAL_DIR%\"}"; LOCAL_DIR="${LOCAL_DIR#\"}"
REPO_PATH="${REPO_PATH%\"}"; REPO_PATH="${REPO_PATH#\"}"
SERVER_IP="${SERVER_IP%\"}"; SERVER_IP="${SERVER_IP#\"}"

# Normalize repo path
if [[ ! "$REPO_PATH" =~ ^/ ]]; then
    REPO_PATH="/$REPO_PATH"
fi
REPO_PATH="${REPO_PATH%/}"
if [ -z "$REPO_PATH" ]; then
    REPO_PATH="/"
fi

# Construct Pentaho server URL (support host:port)
if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

# URL helpers (shared with upload.sh conventions)
build_path_id() {
    local path="$1"
    path="${path#/}"
    if [ -z "$path" ]; then
        echo ":"
    else
        echo ":${path//\//:}"
    fi
}

url_encode() {
    /usr/bin/printf "%s" "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

# --- Temp workspace ---
WORK_DIR=$(mktemp -d)
TMP_ZIP="${WORK_DIR}/export.zip"
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"

cleanup() {
    stop_spinner 2>/dev/null
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# --- Download repository content as zip ---
PATH_ID=$(build_path_id "$REPO_PATH")
ENCODED_PATH_ID=$(url_encode "$PATH_ID")
DOWNLOAD_URL="${PENTAHO_URL}/api/repo/files/${ENCODED_PATH_ID}/download"

info "Pulling repository content..."
info "Repository path:  $REPO_PATH"
info "Local directory:  $LOCAL_DIR"
info "Server:           $PENTAHO_URL"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no changes will be made"
fi
echo ""

# --- Spinner helper ---
spinner_pid=""
start_spinner() {
    local msg="$1"
    (
        chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        i=0
        while true; do
            printf "\r${YELLOW}%s %s${NC}" "${chars:$((i % ${#chars})):1}" "$msg"
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    spinner_pid=$!
}
stop_spinner() {
    if [ -n "$spinner_pid" ] && kill -0 "$spinner_pid" 2>/dev/null; then
        kill "$spinner_pid" 2>/dev/null
        wait "$spinner_pid" 2>/dev/null
    fi
    spinner_pid=""
    printf "\r\033[K"
}

# --- Download ---
start_spinner "Downloading repository content..."

HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TMP_ZIP" \
    --user "${USERNAME}:${PASSWORD}" \
    --location \
    --connect-timeout 10 \
    --retry 3 \
    --retry-delay 2 \
    "$DOWNLOAD_URL")

stop_spinner

if [ "$HTTP_CODE" -ne 200 ]; then
    error "Failed to download repository content (HTTP $HTTP_CODE)"
    if [ -s "$TMP_ZIP" ]; then
        echo "Server response:"
        head -c 500 "$TMP_ZIP"
        echo ""
    fi
    exit 1
fi

ZIP_BYTES=$(wc -c < "$TMP_ZIP" | tr -d ' ')
info "Downloaded $ZIP_BYTES bytes"

# --- Extract ---
start_spinner "Extracting archive..."

unzip -q -o "$TMP_ZIP" -d "$EXTRACT_DIR" || {
    stop_spinner
    error "Failed to extract downloaded archive"
    exit 1
}

stop_spinner
FILE_COUNT=$(find "$EXTRACT_DIR" -type f ! -name "exportManifest.xml" | wc -l | tr -d ' ')
info "Extracted $FILE_COUNT files"

# Remove export manifest — it's Pentaho metadata, not user content
find "$EXTRACT_DIR" -name "exportManifest.xml" -delete 2>/dev/null

# --- Determine content root inside the extract ---
# Pentaho zips nest content under the last component of the repo path.
# e.g. /public/pdc-analysis → zip contains pdc-analysis/utility/...
REPO_BASENAME=$(basename "$REPO_PATH")

if [ -d "$EXTRACT_DIR/$REPO_BASENAME" ]; then
    CONTENT_ROOT="$EXTRACT_DIR/$REPO_BASENAME"
else
    # Fallback: if there's exactly one directory in the extract, use it
    dir_count=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [ "$dir_count" -eq 1 ]; then
        CONTENT_ROOT=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d)
    else
        # No nesting — files are directly at extract root
        CONTENT_ROOT="$EXTRACT_DIR"
    fi
fi

# --- Determine backup directory ---
# Backups go to pdc-analysis/archive/content-backup/<timestamp>/ preserving the
# relative path structure so the main content tree stays clean.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_ROOT="${PROJECT_ROOT}/archive/content-backup/${TIMESTAMP}"

# --- Compare helper ---
# .locale files contain a timestamp comment (line 2) that changes on every export
# even when the actual content is identical. Strip those lines before comparing.
files_match() {
    local file_a="$1"
    local file_b="$2"

    if [[ "$file_a" == *.locale ]]; then
        # Compare ignoring Java properties comment lines (start with #)
        diff -q <(grep -v '^#' "$file_a") <(grep -v '^#' "$file_b") > /dev/null 2>&1
    else
        diff -q "$file_a" "$file_b" > /dev/null 2>&1
    fi
}

# --- Compare and sync ---
info "Comparing $FILE_COUNT server files against local directory..."
if [ "$DRY_RUN" != "true" ]; then
    info "Backups will be saved to: archive/content-backup/$TIMESTAMP/"
fi
echo ""
NEW_COUNT=0
SKIP_COUNT=0
BACKUP_COUNT=0
TOTAL_COUNT=0

while IFS= read -r -d '' server_file; do
    rel_path="${server_file#"$CONTENT_ROOT/"}"
    local_file="${LOCAL_DIR%/}/${rel_path}"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    if [ ! -f "$local_file" ]; then
        # --- New file: doesn't exist locally ---
        if [ "$DRY_RUN" = "true" ]; then
            success "[NEW]      $rel_path"
        else
            mkdir -p "$(dirname "$local_file")"
            cp "$server_file" "$local_file"
            success "[NEW]      $rel_path"
        fi
        NEW_COUNT=$((NEW_COUNT + 1))

    elif files_match "$local_file" "$server_file"; then
        # --- Identical: skip ---
        detail "[SKIP]     $rel_path  (identical)"
        SKIP_COUNT=$((SKIP_COUNT + 1))

    else
        # --- Changed: backup local to archive, copy server version ---
        backup_file="${BACKUP_ROOT}/${rel_path}"
        if [ "$DRY_RUN" = "true" ]; then
            success "[CHANGED]  $rel_path"
            detail "           backup → archive/content-backup/$TIMESTAMP/$rel_path"
        else
            mkdir -p "$(dirname "$backup_file")"
            cp "$local_file" "$backup_file"
            cp "$server_file" "$local_file"
            success "[CHANGED]  $rel_path"
            detail "           backup → archive/content-backup/$TIMESTAMP/$rel_path"
        fi
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
    fi
done < <(find "$CONTENT_ROOT" -type f -print0 | sort -z)

echo ""
info "Sync complete.  Total: $TOTAL_COUNT | New: $NEW_COUNT | Changed: $BACKUP_COUNT | Identical: $SKIP_COUNT"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no files were modified"
fi
