#!/bin/bash

################################################################################
# push-content.sh
#
# Syncs local content UP to Pentaho Server repository. Only pushes files that
# are new or changed locally — pulls the current server state first to compare.
#
# Behavior:
#   - New file (local only):    uploaded to server
#   - Identical file:           skipped
#   - Changed file (differs):   server copy backed up to archive/content-backup/,
#                                local version pushed to server as the current file
#
# Usage:
#   ./push-content.sh [--dry-run] [--smart-title] <local-dir> <repo-path> <server-ip> [username] [password]
#
# Parameters:
#   --dry-run     : Show what would happen without uploading
#   --smart-title : Auto-generate display titles from filenames
#   local-dir     : Local directory containing content to push
#   repo-path     : Target repository path (e.g., /public/pdc-analysis)
#   server-ip     : Pentaho server host or host:port
#   username      : Pentaho username (optional, defaults to 'admin')
#   password      : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./push-content.sh ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
#   ./push-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
#   ./push-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis localhost admin mypassword
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
SMART_TITLE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --smart-title)
            SMART_TITLE="true"
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
    echo "Usage: $0 [--dry-run] [--smart-title] <local-dir> <repo-path> <server-ip> [username] [password]"
    echo ""
    echo "Behavior:"
    echo "  - New files (local only):        uploaded to server"
    echo "  - Identical files:               skipped"
    echo "  - Changed files (local differs): server version backed up to archive/,"
    echo "                                   local version pushed to server"
    echo ""
    echo "Examples:"
    echo "  $0 ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80"
    echo "  $0 --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80"
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

# Validate local directory
if [ ! -d "$LOCAL_DIR" ]; then
    error "Local directory not found: $LOCAL_DIR"
    exit 1
fi

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

REPO_FILES_URL="${PENTAHO_URL}/api/repo/files"
REPO_DIRS_URL="${PENTAHO_URL}/api/repo/dirs"

# --- URL helpers ---
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

RESPONSE_FILE=$(mktemp)
CURL_ERR_FILE=$(mktemp)

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

cleanup() {
    stop_spinner 2>/dev/null
    rm -rf "$WORK_DIR"
    rm -f "$RESPONSE_FILE" "$CURL_ERR_FILE"
}
trap cleanup EXIT

# --- Compare helper (same as pull-content.sh) ---
# .locale files contain a timestamp comment (line 2) that changes on every export
# even when the actual content is identical. Strip comment lines before comparing.
files_match() {
    local file_a="$1"
    local file_b="$2"

    if [[ "$file_a" == *.locale ]]; then
        diff -q <(grep -v '^#' "$file_a") <(grep -v '^#' "$file_b") > /dev/null 2>&1
    else
        diff -q "$file_a" "$file_b" > /dev/null 2>&1
    fi
}

# --- Skip helper (same as upload.sh) ---
should_skip_file() {
    local source_file="$1"
    local base_name
    base_name=$(basename "$source_file")

    # Hidden/system files
    if [[ "$base_name" == .* ]]; then
        return 0
    fi
    # Markdown files
    if [[ "$base_name" == *.md ]]; then
        return 0
    fi
    return 1
}

# --- Smart title helper (same as upload.sh) ---
smart_title_from_filename() {
    local source_file="$1"
    local base_name name_no_ext normalized title
    base_name=$(basename "$source_file")
    name_no_ext="${base_name%.*}"
    normalized=$(printf '%s' "$name_no_ext" | sed -E 's/[-_]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')
    title=$(printf '%s' "$normalized" | awk '{for(i=1;i<=NF;i++){w=tolower($i);$i=toupper(substr(w,1,1))substr(w,2)}print}')
    printf '%s' "$title"
}

# --- Repository helpers (from upload.sh) ---
CREATED_DIRS=""
dir_cached() {
    /usr/bin/printf "%s" "$CREATED_DIRS" | /usr/bin/grep -Fxq "$1"
}
mark_dir_cached() {
    CREATED_DIRS="${CREATED_DIRS}$1
"
}

repo_dir_exists() {
    local full_path="$1"
    local dir_id encoded_dir_id url code
    dir_id=$(build_path_id "$full_path")
    encoded_dir_id=$(url_encode "$dir_id")
    url="${REPO_FILES_URL}/${encoded_dir_id}"
    code=$(curl -sS -w "%{http_code}" -o /dev/null \
        --user "${USERNAME}:${PASSWORD}" -X GET 2>/dev/null "$url")
    [ "$code" -eq 200 ]
}

ensure_repo_dir() {
    local full_path="$1"
    local trimmed="${full_path#/}"
    local current=""

    if [ -z "$trimmed" ]; then return 0; fi

    IFS='/' read -r -a parts <<< "$trimmed"
    for part in "${parts[@]}"; do
        [ -z "$part" ] && continue
        if [ -z "$current" ]; then current="/$part"; else current="$current/$part"; fi
        if [ "$current" = "/public" ] || [ "$current" = "/home" ]; then
            mark_dir_cached "$current"; continue
        fi
        dir_cached "$current" && continue
        if repo_dir_exists "$current"; then mark_dir_cached "$current"; continue; fi

        if [ "$DRY_RUN" = "true" ]; then
            info "Dry run: would create repo dir '$current'"
        else
            local dir_id encoded_dir_id url code
            dir_id=$(build_path_id "$current")
            encoded_dir_id=$(url_encode "$dir_id")
            url="${REPO_DIRS_URL}/${encoded_dir_id}"
            code=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
                --user "${USERNAME}:${PASSWORD}" -X PUT 2>"$CURL_ERR_FILE" "$url")
            if [ "$code" -ne 200 ] && [ "$code" -ne 201 ] && [ "$code" -ne 409 ]; then
                if ! repo_dir_exists "$current"; then
                    if [ "$code" = "000" ]; then
                        info "Directory create returned HTTP 000 for '$current'; continuing and letting upload verify path availability."
                        if [ -s "$CURL_ERR_FILE" ]; then
                            echo "Curl error detail:" >&2
                            cat "$CURL_ERR_FILE" >&2
                        fi
                        mark_dir_cached "$current"
                        continue
                    fi
                    error "Failed to create repo dir '$current' (HTTP $code)"
                    if [ -s "$RESPONSE_FILE" ]; then
                        echo "Server response:" >&2; cat "$RESPONSE_FILE" >&2
                    fi
                    if [ -s "$CURL_ERR_FILE" ]; then
                        echo "Curl error detail:" >&2; cat "$CURL_ERR_FILE" >&2
                    fi
                    return 1
                fi
            fi
        fi
        mark_dir_cached "$current"
    done
    return 0
}

upload_single_file() {
    local source_file="$1"
    local target_dir="$2"
    local title="$3"
    local filename
    filename=$(basename "$source_file")

    if ! ensure_repo_dir "$target_dir"; then return 1; fi

    if [ "$DRY_RUN" = "true" ]; then return 0; fi

    local full_repo_path="${target_dir%/}/${filename}"
    local path_id encoded_path_id upload_url
    path_id=$(build_path_id "$full_repo_path")
    encoded_path_id=$(url_encode "$path_id")
    upload_url="${REPO_FILES_URL}/${encoded_path_id}?overwrite=true"

    local http_code
    http_code=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${source_file}" \
        2>"$CURL_ERR_FILE" \
        "${upload_url}")

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        # Verify file actually exists on server after upload
        local verify_url="${REPO_FILES_URL}/${encoded_path_id}"
        local verify_code
        verify_code=$(curl -sS -w "%{http_code}" -o /dev/null \
            --user "${USERNAME}:${PASSWORD}" -X GET 2>/dev/null "$verify_url")
        if [ "$verify_code" -ne 200 ]; then
            error "Upload reported success but file not found on server: '$full_repo_path' (verify HTTP $verify_code)"
            return 1
        fi
        # Hide .locale files in the UI
        if [[ "$filename" == *.locale ]]; then
            if ! set_locale_hidden "$full_repo_path"; then
                error "File uploaded but failed to set hidden flag: '$full_repo_path'"
                return 1
            fi
        fi
        # Set title if requested
        if [ -n "$title" ]; then
            if ! set_file_title "$full_repo_path" "$title"; then
                error "File uploaded but failed to set title: '$full_repo_path'"
                return 1
            fi
        fi
        return 0
    fi

    if [ "$http_code" = "000" ]; then
        error "Network error uploading '$full_repo_path' (HTTP 000 — curl could not reach server)"
        if [ -s "$CURL_ERR_FILE" ]; then
            echo "Curl error detail:" >&2; cat "$CURL_ERR_FILE" >&2
        fi
    else
        error "Upload failed for '$full_repo_path' (HTTP $http_code)"
        if [ -s "$RESPONSE_FILE" ]; then
            echo "Server response:" >&2; cat "$RESPONSE_FILE" >&2
        fi
    fi
    return 1
}

set_locale_hidden() {
    local repo_file_path="$1"
    local path_id encoded_path_id url payload code
    path_id=$(build_path_id "$repo_file_path")
    encoded_path_id=$(url_encode "$path_id")
    url="${REPO_FILES_URL}/${encoded_path_id}/metadata"
    payload='{"stringKeyStringValueDto":[{"key":"_PERM_HIDDEN","value":"true"}]}'
    code=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" -d "$payload" "$url" 2>/dev/null)
    if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
        return 0
    fi
    error "Failed to set hidden metadata for '$repo_file_path' (HTTP $code)"
    return 1
}

set_file_title() {
    local repo_file_path="$1"
    local title="$2"
    local path_id encoded_path_id escaped_title
    path_id=$(build_path_id "$repo_file_path")
    encoded_path_id=$(url_encode "$path_id")
    escaped_title=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    # Locale properties (primary — this is what BA Server console displays)
    local locale_url="${REPO_FILES_URL}/${encoded_path_id}/localeProperties?locale=default"
    local locale_payload="[{\"key\":\"file.title\",\"value\":\"$escaped_title\"},{\"key\":\"title\",\"value\":\"$escaped_title\"}]"
    local code
    code=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" -d "$locale_payload" "$locale_url" 2>/dev/null)

    # Metadata fallback (for HTML and other files without locale support)
    local meta_url="${REPO_FILES_URL}/${encoded_path_id}/metadata"
    local meta_payload="{\"stringKeyStringValueDto\":[{\"key\":\"file.title\",\"value\":\"$escaped_title\"}]}"
    curl -s -o /dev/null --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" -d "$meta_payload" "$meta_url" 2>/dev/null

    if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
        return 0
    fi
    error "Failed to set title for '$repo_file_path' (HTTP $code)"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

info "Pushing local content to server..."
info "Local directory:  $LOCAL_DIR"
info "Repository path:  $REPO_PATH"
info "Server:           $PENTAHO_URL"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no changes will be made"
fi
if [ "$SMART_TITLE" = "true" ]; then
    info "Smart title mode enabled"
fi
echo ""

# ── Step 1: Pull current server content for comparison ──────────────────────
PATH_ID=$(build_path_id "$REPO_PATH")
ENCODED_PATH_ID=$(url_encode "$PATH_ID")
DOWNLOAD_URL="${PENTAHO_URL}/api/repo/files/${ENCODED_PATH_ID}/download"

start_spinner "Downloading current server content for comparison..."

HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TMP_ZIP" \
    --user "${USERNAME}:${PASSWORD}" \
    --location \
    --connect-timeout 10 \
    --retry 3 \
    --retry-delay 2 \
    "$DOWNLOAD_URL")

stop_spinner

SERVER_HAS_CONTENT="true"
if [ "$HTTP_CODE" -eq 404 ]; then
    info "Repository path does not exist yet — all local files will be pushed as new"
    SERVER_HAS_CONTENT="false"
elif [ "$HTTP_CODE" -ne 200 ]; then
    error "Failed to download server content (HTTP $HTTP_CODE)"
    if [ -s "$TMP_ZIP" ]; then
        echo "Server response:"
        head -c 500 "$TMP_ZIP"
        echo ""
    fi
    exit 1
fi

CONTENT_ROOT=""
if [ "$SERVER_HAS_CONTENT" = "true" ]; then
    ZIP_BYTES=$(wc -c < "$TMP_ZIP" | tr -d ' ')
    info "Downloaded $ZIP_BYTES bytes from server"

    start_spinner "Extracting server content..."
    unzip -q -o "$TMP_ZIP" -d "$EXTRACT_DIR" || {
        stop_spinner
        error "Failed to extract server archive"
        exit 1
    }
    stop_spinner

    SERVER_FILE_COUNT=$(find "$EXTRACT_DIR" -type f ! -name "exportManifest.xml" | wc -l | tr -d ' ')
    info "Extracted $SERVER_FILE_COUNT server files for comparison"

    # Remove export manifests
    find "$EXTRACT_DIR" -name "exportManifest.xml" -delete 2>/dev/null

    # Determine content root
    REPO_BASENAME=$(basename "$REPO_PATH")
    if [ -d "$EXTRACT_DIR/$REPO_BASENAME" ]; then
        CONTENT_ROOT="$EXTRACT_DIR/$REPO_BASENAME"
    else
        dir_count=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        if [ "$dir_count" -eq 1 ]; then
            CONTENT_ROOT=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d)
        else
            CONTENT_ROOT="$EXTRACT_DIR"
        fi
    fi
fi

# ── Step 2: Backup directory setup ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_ROOT="${PROJECT_ROOT}/archive/content-backup/${TIMESTAMP}"

# ── Step 3: Walk local files, compare, and push deltas ──────────────────────
LOCAL_DIR_ABS="$(cd "$LOCAL_DIR" && pwd)"
LOCAL_FILE_COUNT=$(find "$LOCAL_DIR_ABS" -type f | wc -l | tr -d ' ')
info "Comparing $LOCAL_FILE_COUNT local files against server..."
if [ "$DRY_RUN" != "true" ]; then
    info "Server backups will be saved to: archive/content-backup/$TIMESTAMP/"
fi
echo ""

NEW_COUNT=0
SKIP_COUNT=0
CHANGED_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

while IFS= read -r -d '' local_file; do
    rel_path="${local_file#"$LOCAL_DIR_ABS/"}"

    if should_skip_file "$local_file"; then
        detail "[SKIP]     $rel_path  (excluded)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    # Determine the matching server file (if any)
    if [ -n "$CONTENT_ROOT" ]; then
        server_file="${CONTENT_ROOT}/${rel_path}"
    else
        server_file=""
    fi

    # Figure out target repo dir for this file
    rel_dir=$(dirname "$rel_path")
    if [ "$rel_dir" = "." ]; then
        target_dir="$REPO_PATH"
    else
        target_dir="$REPO_PATH/$rel_dir"
    fi

    # Resolve title
    title=""
    if [ "$SMART_TITLE" = "true" ]; then
        # Don't set titles on .locale or .properties files
        case "$local_file" in
            *.locale|*.properties|*.css) ;;
            *) title=$(smart_title_from_filename "$local_file") ;;
        esac
    fi

    if [ -z "$server_file" ] || [ ! -f "$server_file" ]; then
        # --- New file: doesn't exist on server ---
        if [ "$DRY_RUN" = "true" ]; then
            success "[NEW]      $rel_path"
            if [ -n "$title" ]; then
                detail "           title → $title"
            fi
        else
            if upload_single_file "$local_file" "$target_dir" "$title"; then
                success "[PUSH]     $rel_path"
                if [ -n "$title" ]; then
                    detail "           title → $title"
                fi
            else
                error "[FAIL]     $rel_path"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                continue
            fi
        fi
        NEW_COUNT=$((NEW_COUNT + 1))

    elif files_match "$local_file" "$server_file"; then
        # --- Identical: skip ---
        detail "[SKIP]     $rel_path  (identical)"
        SKIP_COUNT=$((SKIP_COUNT + 1))

    else
        # --- Changed: backup server version, push local ---
        backup_file="${BACKUP_ROOT}/${rel_path}"
        if [ "$DRY_RUN" = "true" ]; then
            success "[CHANGED]  $rel_path"
            detail "           server backup → archive/content-backup/$TIMESTAMP/$rel_path"
            if [ -n "$title" ]; then
                detail "           title → $title"
            fi
        else
            # Backup the server version locally
            mkdir -p "$(dirname "$backup_file")"
            cp "$server_file" "$backup_file"

            if upload_single_file "$local_file" "$target_dir" "$title"; then
                success "[PUSH]     $rel_path"
                detail "           server backup → archive/content-backup/$TIMESTAMP/$rel_path"
                if [ -n "$title" ]; then
                    detail "           title → $title"
                fi
            else
                error "[FAIL]     $rel_path"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                continue
            fi
        fi
        CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
done < <(find "$LOCAL_DIR_ABS" -type f -print0 | sort -z)

echo ""
info "Sync complete.  Processed: $TOTAL_COUNT | New: $NEW_COUNT | Changed: $CHANGED_COUNT | Identical: $SKIP_COUNT | Failed: $FAIL_COUNT"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no files were uploaded"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
