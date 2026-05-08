#!/bin/bash

################################################################################
# push-home-files.sh
#
# Pushes downloaded /home content to a target Pentaho server by uploading each
# file individually using the REST API. Mirrors the directory structure from
# the local download into the /home tree on the target server.
#
# Usage:
#   ./push-home-files.sh [--dry-run] <local-dir> <server-ip> [username] [password]
#
# Examples:
#   ./push-home-files.sh ./home-backup 10.80.230.225:80
#   ./push-home-files.sh --dry-run ./home-backup 10.80.230.225:80 admin password
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

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    error "Usage: $0 [--dry-run] <local-dir> <server-ip> [username] [password]"
    exit 1
fi

LOCAL_DIR="$1"
SERVER_IP="$2"
USERNAME="${3:-admin}"
PASSWORD="${4:-password}"

if [ ! -d "$LOCAL_DIR" ]; then
    error "Directory not found: $LOCAL_DIR"
    exit 1
fi

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

info "Pushing /home content to server..."
info "Server:  $PENTAHO_URL"
info "Source:  $LOCAL_DIR"
if [ "$DRY_RUN" = "true" ]; then info "DRY RUN — no files will be uploaded"; fi
echo ""

REPO_FILES_URL="${PENTAHO_URL}/api/repo/files"
REPO_DIRS_URL="${PENTAHO_URL}/api/repo/dirs"

TOTAL=0
UPLOADED=0
FAILED=0
SKIPPED=0

CREATED_DIRS=""
ensure_repo_dir() {
    local full_path="$1"
    local trimmed="${full_path#/}"
    local current=""

    if [ -z "$trimmed" ]; then return 0; fi

    IFS='/' read -r -a parts <<< "$trimmed"
    for part in "${parts[@]}"; do
        [ -z "$part" ] && continue
        if [ -z "$current" ]; then
            current="/$part"
        else
            current="$current/$part"
        fi

        # Skip known root dirs
        if [ "$current" = "/home" ]; then
            continue
        fi

        # Skip if already created
        if echo "$CREATED_DIRS" | grep -Fxq "$current" 2>/dev/null; then
            continue
        fi

        if [ "$DRY_RUN" = "true" ]; then
            detail "[DRY RUN] Would create dir: $current"
        else
            local dir_id
            dir_id=$(build_path_id "$current")
            local encoded_dir_id
            encoded_dir_id=$(url_encode "$dir_id")
            local url="${REPO_DIRS_URL}/${encoded_dir_id}"
            local code
            code=$($CURL_BIN -sS -w "%{http_code}" -o /dev/null \
                --user "${USERNAME}:${PASSWORD}" \
                -X PUT \
                "$url" 2>/dev/null)
            # 200/201 = created, 409 = already exists — all ok
            if [ "$code" -ne 200 ] && [ "$code" -ne 201 ] && [ "$code" -ne 409 ]; then
                if [ "$code" = "000" ]; then
                    info "Directory create returned HTTP 000 for '$current'; continuing..."
                else
                    error "Failed to create repo dir '$current' (HTTP $code)"
                fi
            fi
        fi
        CREATED_DIRS="${CREATED_DIRS}${current}
"
    done
}

upload_single_file() {
    local local_file="$1"
    local repo_path="$2"

    ((TOTAL++)) || true

    local repo_dir
    repo_dir=$(dirname "$repo_path")
    local filename
    filename=$(basename "$repo_path")

    ensure_repo_dir "$repo_dir"

    if [ "$DRY_RUN" = "true" ]; then
        detail "[DRY RUN] ${repo_path}"
        ((SKIPPED++)) || true
        return
    fi

    # If file is a zip-wrapped export bundle (.ktr, .kjb), extract raw content
    local upload_source="$local_file"
    local tmp_extracted=""
    if [[ "$filename" == *.ktr || "$filename" == *.kjb ]]; then
        if file "$local_file" 2>/dev/null | grep -q "Zip archive"; then
            tmp_extracted=$(mktemp "/tmp/push-home-XXXXXX")
            if unzip -o -p "$local_file" "$filename" > "$tmp_extracted" 2>/dev/null && [ -s "$tmp_extracted" ]; then
                upload_source="$tmp_extracted"
            else
                # Not a valid export bundle, use original file
                upload_source="$local_file"
            fi
        fi
    fi

    local path_id
    path_id=$(build_path_id "$repo_path")
    local encoded_path_id
    encoded_path_id=$(url_encode "$path_id")
    local upload_url="${REPO_FILES_URL}/${encoded_path_id}?overwrite=true"

    local http_code
    http_code=$($CURL_BIN -sS -w "%{http_code}" -o /dev/null \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${upload_source}" \
        --connect-timeout 10 --max-time 120 \
        "$upload_url" 2>/dev/null)

    # Clean up temp file
    [ -n "$tmp_extracted" ] && [ -f "$tmp_extracted" ] && rm -f "$tmp_extracted"

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        # Verify file actually exists on server after upload
        local verify_url="${REPO_FILES_URL}/${encoded_path_id}"
        local verify_code
        verify_code=$($CURL_BIN -sS -w "%{http_code}" -o /dev/null \
            --user "${USERNAME}:${PASSWORD}" -X GET 2>/dev/null "$verify_url")
        if [ "$verify_code" -ne 200 ]; then
            error "  Upload reported success but file not found on server (verify HTTP $verify_code): ${repo_path}"
            ((FAILED++)) || true
        else
            success "  Uploaded: ${repo_path}"
            ((UPLOADED++)) || true
        fi
    elif [ "$http_code" = "000" ]; then
        error "  Network error (HTTP 000 — curl could not reach server): ${repo_path}"
        ((FAILED++)) || true
    else
        error "  Failed ($http_code): ${repo_path}"
        ((FAILED++)) || true
    fi
}

# Resolve absolute path for LOCAL_DIR
LOCAL_DIR_ABS=$(cd "$LOCAL_DIR" && pwd)

# Find all files and upload them
# Use a temp file listing to avoid subshell issues
FILELIST=$(mktemp)
trap 'rm -f "$FILELIST"' EXIT

find "$LOCAL_DIR_ABS" -type f | sort > "$FILELIST"

while IFS= read -r local_file; do
    # Build the repo path: strip the local base dir, prepend /home
    rel_path="${local_file#$LOCAL_DIR_ABS/}"
    repo_path="/home/${rel_path}"
    upload_single_file "$local_file" "$repo_path"
done < "$FILELIST"

echo ""
echo "────────────────────────────────────────"
echo "UPLOAD SUMMARY"
echo "  Total:    $TOTAL"
echo "  Uploaded: $UPLOADED"
echo "  Failed:   $FAILED"
echo "  Skipped:  $SKIPPED"
echo "────────────────────────────────────────"

if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no files were uploaded"
fi
