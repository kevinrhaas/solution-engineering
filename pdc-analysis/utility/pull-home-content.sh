#!/bin/bash

################################################################################
# pull-home-content.sh
#
# Downloads /home directory content from Pentaho Server using the full backup
# API endpoint, then extracts only the /home portion. This works around the
# 403 restriction on /home directory exports in older Pentaho versions.
#
# Usage:
#   ./pull-home-content.sh [--dry-run] <local-dir> <server-ip> [username] [password]
#
# Examples:
#   ./pull-home-content.sh ./home-backup 10.80.230.123:80
#   ./pull-home-content.sh --dry-run ./home-backup 10.80.230.123:80 admin password
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
info()    { echo -e "${YELLOW}INFO: $1${NC}"; }
detail()  { echo -e "${CYAN}  $1${NC}"; }

for cmd in curl unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd command not found. Please install $cmd."
        exit 1
    fi
done

DRY_RUN="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        *) break ;;
    esac
done

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    error "Usage: $0 [--dry-run] <local-dir> <server-ip> [username] [password]"
    exit 1
fi

LOCAL_DIR="$1"
SERVER_IP="$2"
USERNAME="${3:-admin}"
PASSWORD="${4:-password}"

if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

BACKUP_URL="${PENTAHO_URL}/api/repo/files/backup"

info "Downloading full repository backup..."
info "Server:    $PENTAHO_URL"
info "Target:    $LOCAL_DIR"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no changes will be made"
    info "Would download backup from: $BACKUP_URL"
    info "Would extract /home/ content to: $LOCAL_DIR"
    exit 0
fi

WORK_DIR=$(mktemp -d)
BACKUP_ZIP="${WORK_DIR}/backup.zip"
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# --- Spinner ---
spinner_pid=""
start_spinner() {
    local msg="$1"
    ( chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; i=0
      while true; do printf "\r${YELLOW}%s %s${NC}" "${chars:$((i % ${#chars})):1}" "$msg"; i=$((i+1)); sleep 0.1; done
    ) &
    spinner_pid=$!
}
stop_spinner() {
    if [ -n "$spinner_pid" ] && kill -0 "$spinner_pid" 2>/dev/null; then
        kill "$spinner_pid" 2>/dev/null; wait "$spinner_pid" 2>/dev/null
    fi
    spinner_pid=""; printf "\r\033[K"
}

start_spinner "Downloading full repository backup (this may take a while)..."

HTTP_CODE=$(curl -s -w "%{http_code}" -o "$BACKUP_ZIP" \
    --connect-timeout 30 \
    --max-time 600 \
    --user "${USERNAME}:${PASSWORD}" \
    --location \
    "$BACKUP_URL")

stop_spinner

if [ "$HTTP_CODE" -ne 200 ]; then
    error "Backup download failed (HTTP $HTTP_CODE)"
    if [ -s "$BACKUP_ZIP" ]; then
        echo "Response:" ; head -c 500 "$BACKUP_ZIP"; echo ""
    fi
    exit 1
fi

BACKUP_SIZE=$(wc -c < "$BACKUP_ZIP" | tr -d ' ')
info "Downloaded backup: $(( BACKUP_SIZE / 1024 )) KB"

start_spinner "Extracting backup..."
unzip -q -o "$BACKUP_ZIP" -d "$EXTRACT_DIR"
stop_spinner

# Find the home directory in the extracted content
HOME_DIR=""
if [ -d "$EXTRACT_DIR/home" ]; then
    HOME_DIR="$EXTRACT_DIR/home"
elif [ -d "$EXTRACT_DIR/pentaho-solutions/home" ]; then
    HOME_DIR="$EXTRACT_DIR/pentaho-solutions/home"
fi

if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    info "Listing extracted structure for debugging:"
    find "$EXTRACT_DIR" -maxdepth 3 -type d | head -30
    error "Could not find /home directory in backup"
    exit 1
fi

# Copy home content to local dir
mkdir -p "$LOCAL_DIR"
cp -R "$HOME_DIR"/* "$LOCAL_DIR/" 2>/dev/null || true

# Count results
FILE_COUNT=$(find "$LOCAL_DIR" -type f | wc -l | tr -d ' ')
DIR_COUNT=$(find "$LOCAL_DIR" -type d | wc -l | tr -d ' ')

success "Extracted home directory content"
info "  Files:       $FILE_COUNT"
info "  Directories: $DIR_COUNT"
info "  Location:    $LOCAL_DIR"

echo ""
info "Directory structure:"
find "$LOCAL_DIR" -maxdepth 2 -type d | sort | while read -r d; do
    count=$(find "$d" -maxdepth 1 -type f | wc -l | tr -d ' ')
    rel="${d#$LOCAL_DIR}"
    [ -z "$rel" ] && rel="/"
    detail "${rel}  ($count files)"
done
