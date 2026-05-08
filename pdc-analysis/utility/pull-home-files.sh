#!/bin/bash

################################################################################
# pull-home-files.sh
#
# Downloads individual files from Pentaho /home directories using the REST API
# generatedContent endpoint, which bypasses the 403 restriction on the directory
# download/export endpoint in older Pentaho versions.
#
# Recursively lists all files under the given repo path and downloads them
# one at a time.
#
# Usage:
#   ./pull-home-files.sh [--dry-run] <local-dir> <repo-path> <server-ip> [username] [password]
#
# Examples:
#   ./pull-home-files.sh ./home-backup /home 10.80.230.123:80
#   ./pull-home-files.sh --dry-run ./admin-files /home/admin 10.80.230.123:80 admin password
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

if ! command -v curl &> /dev/null; then
    error "curl command not found."
    exit 1
fi

CURL_BIN="/usr/bin/curl"
if [ ! -x "$CURL_BIN" ]; then
    CURL_BIN="curl"
fi

DRY_RUN="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        *) break ;;
    esac
done

if [ $# -lt 3 ] || [ $# -gt 5 ]; then
    error "Usage: $0 [--dry-run] <local-dir> <repo-path> <server-ip> [username] [password]"
    exit 1
fi

LOCAL_DIR="$1"
REPO_PATH="$2"
SERVER_IP="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

if [[ ! "$REPO_PATH" =~ ^/ ]]; then REPO_PATH="/$REPO_PATH"; fi
REPO_PATH="${REPO_PATH%/}"

if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

url_encode() {
    /usr/bin/printf "%s" "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

build_path_id() {
    local path="$1"
    path="${path#/}"
    if [ -z "$path" ]; then echo ":"; else echo ":${path//\//:}"; fi
}

info "Pulling files from ${REPO_PATH}..."
info "Server:   $PENTAHO_URL"
info "Local:    $LOCAL_DIR"
if [ "$DRY_RUN" = "true" ]; then info "DRY RUN — no files will be written"; fi
echo ""

# Counters
TOTAL=0
DOWNLOADED=0
FAILED=0
SKIPPED=0

# Temp dir for listing files
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Recursive function to list and download files
pull_directory() {
    local dir_path="$1"
    local local_base="$2"

    local path_id
    path_id=$(build_path_id "$dir_path")
    local encoded_pid
    encoded_pid=$(url_encode "$path_id")

    # Get children listing
    local children_url="${PENTAHO_URL}/api/repo/files/${encoded_pid}/children"
    local response
    response=$($CURL_BIN -s --user "${USERNAME}:${PASSWORD}" \
        --connect-timeout 10 --max-time 30 \
        -H "Accept: application/json" "$children_url" 2>/dev/null)

    if [ -z "$response" ]; then
        error "No response listing: $dir_path"
        return
    fi

    # Parse JSON into a temp file (avoid subshell from pipe)
    local listing_file
    listing_file=$(mktemp "$TMPDIR_WORK/listing.XXXXXX")

    echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    items = data.get('repositoryFileDto', [])
    if isinstance(items, dict):
        items = [items]
    for item in items:
        folder = '1' if item.get('folder') else '0'
        path = item.get('path', '')
        name = item.get('name', '')
        print(f'{folder}\t{path}\t{name}')
except:
    pass
" > "$listing_file"

    # Read from file (not pipe) so we stay in the current shell
    while IFS=$'\t' read -r is_folder item_path item_name; do
        if [ "$is_folder" = "1" ]; then
            # Recurse into subdirectory
            info "Directory: ${item_path}"
            pull_directory "$item_path" "$local_base"
        else
            # Download file
            ((TOTAL++)) || true

            # Build relative path from repo root
            local rel_path="${item_path#$REPO_PATH/}"
            local local_file="${local_base}/${rel_path}"
            local local_dir_for_file
            local_dir_for_file=$(dirname "$local_file")

            if [ "$DRY_RUN" = "true" ]; then
                detail "[DRY RUN] ${item_path}"
                ((SKIPPED++)) || true
                continue
            fi

            # Create target directory
            mkdir -p "$local_dir_for_file"

            # Download using the inline endpoint
            local file_path_id
            file_path_id=$(build_path_id "$item_path")
            local encoded_file_pid
            encoded_file_pid=$(url_encode "$file_path_id")

            # Try /api/repo/files/{pathId}/inline first (reads raw content)
            local http_code
            http_code=$($CURL_BIN -s -w "%{http_code}" -o "$local_file" \
                --connect-timeout 10 --max-time 120 \
                --user "${USERNAME}:${PASSWORD}" \
                "${PENTAHO_URL}/api/repo/files/${encoded_file_pid}/inline" 2>/dev/null)

            if [ "$http_code" -eq 200 ] && [ -s "$local_file" ]; then
                success "  Downloaded: ${rel_path}"
                ((DOWNLOADED++)) || true
            else
                # Fallback to /download endpoint
                http_code=$($CURL_BIN -s -w "%{http_code}" -o "$local_file" \
                    --connect-timeout 10 --max-time 120 \
                    --user "${USERNAME}:${PASSWORD}" \
                    "${PENTAHO_URL}/api/repo/files/${encoded_file_pid}/download" 2>/dev/null)

                if [ "$http_code" -eq 200 ] && [ -s "$local_file" ]; then
                    success "  Downloaded: ${rel_path}"
                    ((DOWNLOADED++)) || true
                else
                    error "  Failed ($http_code): ${rel_path}"
                    rm -f "$local_file" 2>/dev/null
                    ((FAILED++)) || true
                fi
            fi
        fi
    done < "$listing_file"

    rm -f "$listing_file"
}

pull_directory "$REPO_PATH" "$LOCAL_DIR"

echo ""
echo "────────────────────────────────────────"
echo "DOWNLOAD SUMMARY"
echo "  Total:      $TOTAL"
echo "  Downloaded: $DOWNLOADED"
echo "  Failed:     $FAILED"
echo "  Skipped:    $SKIPPED"
echo "────────────────────────────────────────"

if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no files were written"
fi
