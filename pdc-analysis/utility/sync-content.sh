#!/bin/bash

################################################################################
# sync-content.sh
#
# Bidirectional content sync between a local directory and Pentaho Server
# repository. Combines pull-content.sh and push-content.sh into a single
# operation with timestamp-based conflict resolution.
#
# File states:
#   LOCAL_ONLY  → push to server
#   SERVER_ONLY → pull to local
#   IDENTICAL   → skip
#   CONFLICT    → newer file wins (by modification time), loser is archived
#
# Conflict resolution:
#   Default:          newer timestamp wins
#   --prefer-local  : local always wins on conflicts
#   --prefer-server : server always wins on conflicts
#
# Usage:
#   ./sync-content.sh [flags] <local-dir> <repo-path> <server-ip> [username] [password]
#
# Flags:
#   --dry-run        : Show what would happen without making changes
#   --smart-title    : Auto-generate display titles from filenames
#   --prefer-local   : On conflicts, always use local version
#   --prefer-server  : On conflicts, always use server version
#
# Examples:
#   ./sync-content.sh --dry-run ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
#   ./sync-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
#   ./sync-content.sh --prefer-local ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
#
# Requirements:
#   - curl, unzip
################################################################################

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

error()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
info()    { echo -e "${YELLOW}INFO: $1${NC}"; }
detail()  { echo -e "${CYAN}  $1${NC}"; }
conflict(){ echo -e "${MAGENTA}$1${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════════
# PREREQUISITES
# ═══════════════════════════════════════════════════════════════════════════════

for cmd in curl unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd command not found. Please install $cmd."
        exit 1
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

DRY_RUN="false"
SMART_TITLE="false"
PREFER="auto"   # auto | local | server

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN="true";        shift ;;
        --smart-title)    SMART_TITLE="true";    shift ;;
        --prefer-local)   PREFER="local";        shift ;;
        --prefer-server)  PREFER="server";       shift ;;
        *)                break ;;
    esac
done

if [ $# -lt 3 ] || [ $# -gt 5 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [flags] <local-dir> <repo-path> <server-ip> [username] [password]"
    echo ""
    echo "Flags:"
    echo "  --dry-run        Show plan without making changes"
    echo "  --smart-title    Auto-generate display titles"
    echo "  --prefer-local   On conflicts, always use local version"
    echo "  --prefer-server  On conflicts, always use server version"
    echo ""
    echo "Conflict resolution (default):"
    echo "  Files that differ are resolved by modification timestamp — newer wins."
    echo "  The losing version is archived under archive/content-backup/<timestamp>/."
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80"
    echo "  $0 --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80"
    echo "  $0 --prefer-local ./content/public/pdc-analysis /public/pdc-analysis localhost admin pass"
    exit 1
fi

LOCAL_DIR="$1"
REPO_PATH="$2"
SERVER_IP="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

# Strip quotes
LOCAL_DIR="${LOCAL_DIR%\"}"; LOCAL_DIR="${LOCAL_DIR#\"}"
REPO_PATH="${REPO_PATH%\"}"; REPO_PATH="${REPO_PATH#\"}"
SERVER_IP="${SERVER_IP%\"}"; SERVER_IP="${SERVER_IP#\"}"

# Validate local directory
if [ ! -d "$LOCAL_DIR" ]; then
    error "Local directory not found: $LOCAL_DIR"
    exit 1
fi

# Normalize repo path
if [[ ! "$REPO_PATH" =~ ^/ ]]; then REPO_PATH="/$REPO_PATH"; fi
REPO_PATH="${REPO_PATH%/}"
if [ -z "$REPO_PATH" ]; then REPO_PATH="/"; fi

# Construct Pentaho server URL (support host:port)
if [[ "$SERVER_IP" == *":"* ]]; then
    PENTAHO_URL="http://${SERVER_IP}/pentaho"
else
    PENTAHO_URL="http://${SERVER_IP}:8080/pentaho"
fi

REPO_FILES_URL="${PENTAHO_URL}/api/repo/files"
REPO_DIRS_URL="${PENTAHO_URL}/api/repo/dirs"

# ═══════════════════════════════════════════════════════════════════════════════
# URL / PATH HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

build_path_id() {
    local path="$1"; path="${path#/}"
    if [ -z "$path" ]; then echo ":"; else echo ":${path//\//:}"; fi
}

url_encode() {
    /usr/bin/printf "%s" "$1" | /usr/bin/xxd -plain | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\(..\)/%\1/g'
}

# ═══════════════════════════════════════════════════════════════════════════════
# FILE COMPARISON
# ═══════════════════════════════════════════════════════════════════════════════

# .locale files have an auto-generated timestamp comment on line 2 that changes
# on every server export — strip comment lines before comparing.
files_match() {
    local file_a="$1" file_b="$2"
    if [[ "$file_a" == *.locale ]]; then
        diff -q <(grep -v '^#' "$file_a") <(grep -v '^#' "$file_b") > /dev/null 2>&1
    else
        diff -q "$file_a" "$file_b" > /dev/null 2>&1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SKIP / TITLE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

should_skip_file() {
    local base_name
    base_name=$(basename "$1")
    [[ "$base_name" == .* ]] && return 0
    [[ "$base_name" == *.md ]] && return 0
    return 1
}

smart_title_from_filename() {
    local base_name name_no_ext normalized title
    base_name=$(basename "$1")
    name_no_ext="${base_name%.*}"
    normalized=$(printf '%s' "$name_no_ext" | sed -E 's/[-_]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')
    title=$(printf '%s' "$normalized" | awk '{for(i=1;i<=NF;i++){w=tolower($i);$i=toupper(substr(w,1,1))substr(w,2)}print}')
    printf '%s' "$title"
}

resolve_title() {
    local filepath="$1"
    if [ "$SMART_TITLE" = "true" ]; then
        case "$filepath" in
            *.locale|*.properties|*.css) echo "" ;;
            *) smart_title_from_filename "$filepath" ;;
        esac
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIMESTAMP HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# Get file modification time as epoch seconds (macOS and Linux compatible)
get_mtime() {
    local file="$1"
    if stat -f %m "$file" 2>/dev/null; then
        return
    fi
    # Linux fallback
    stat -c %Y "$file" 2>/dev/null
}

# Look up server file modification time from the tree API index.
# Falls back to stat on the extracted file if the API index is unavailable.
get_server_mtime() {
    local rel_path="$1"
    if [ -s "${SERVER_MTIME_INDEX:-}" ]; then
        local result
        result=$(awk -F'\t' -v p="$rel_path" '$1 == p {print $2; exit}' "$SERVER_MTIME_INDEX")
        if [ -n "$result" ]; then
            echo "$result"
            return
        fi
    fi
    # Fallback: stat on extracted file
    [ -n "$CONTENT_ROOT" ] && get_mtime "${CONTENT_ROOT}/${rel_path}"
}

# Format epoch to human-readable
format_time() {
    local epoch="$1"
    if [ -z "$epoch" ] || [ "$epoch" = "0" ]; then
        echo "unknown"
        return
    fi
    # macOS
    if date -r "$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null; then
        return
    fi
    # Linux fallback
    date -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$epoch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# REPOSITORY HELPERS (for pushing to server)
# ═══════════════════════════════════════════════════════════════════════════════

CREATED_DIRS=""
dir_cached()     { /usr/bin/printf "%s" "$CREATED_DIRS" | /usr/bin/grep -Fxq "$1"; }
mark_dir_cached(){ CREATED_DIRS="${CREATED_DIRS}$1
"; }

RESPONSE_FILE=$(mktemp)
CURL_ERR_FILE=$(mktemp)

repo_dir_exists() {
    local dir_id encoded url code
    dir_id=$(build_path_id "$1")
    encoded=$(url_encode "$dir_id")
    url="${REPO_FILES_URL}/${encoded}"
    code=$(curl -sS -w "%{http_code}" -o /dev/null \
        --user "${USERNAME}:${PASSWORD}" -X GET 2>/dev/null "$url")
    [ "$code" -eq 200 ]
}

ensure_repo_dir() {
    local full_path="$1" trimmed="${1#/}" current=""
    [ -z "$trimmed" ] && return 0

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
            true  # silently note it
        else
            local dir_id encoded url code
            dir_id=$(build_path_id "$current")
            encoded=$(url_encode "$dir_id")
            url="${REPO_DIRS_URL}/${encoded}"
            code=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
                --user "${USERNAME}:${PASSWORD}" -X PUT 2>"$CURL_ERR_FILE" "$url")
            if [ "$code" -ne 200 ] && [ "$code" -ne 201 ] && [ "$code" -ne 409 ]; then
                if ! repo_dir_exists "$current"; then
                    error "Failed to create repo dir '$current' (HTTP $code)"
                    return 1
                fi
            fi
        fi
        mark_dir_cached "$current"
    done
    return 0
}

upload_single_file() {
    local source_file="$1" target_dir="$2" title="$3"
    local filename
    filename=$(basename "$source_file")

    ensure_repo_dir "$target_dir" || return 1
    [ "$DRY_RUN" = "true" ] && return 0

    local full_repo_path="${target_dir%/}/${filename}"
    local path_id encoded upload_url http_code
    path_id=$(build_path_id "$full_repo_path")
    encoded=$(url_encode "$path_id")
    upload_url="${REPO_FILES_URL}/${encoded}?overwrite=true"

    http_code=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${source_file}" 2>"$CURL_ERR_FILE" "${upload_url}")

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        [[ "$filename" == *.locale ]] && set_locale_hidden "$full_repo_path"
        [ -n "$title" ] && set_file_title "$full_repo_path" "$title"
        return 0
    fi
    error "Upload failed for '$full_repo_path' (HTTP $http_code)"
    return 1
}

set_locale_hidden() {
    local path_id encoded url payload
    path_id=$(build_path_id "$1"); encoded=$(url_encode "$path_id")
    url="${REPO_FILES_URL}/${encoded}/metadata"
    payload='{"stringKeyStringValueDto":[{"key":"_PERM_HIDDEN","value":"true"}]}'
    curl -s -o /dev/null --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" -d "$payload" "$url" 2>/dev/null
}

set_file_title() {
    local path_id encoded escaped_title
    path_id=$(build_path_id "$1"); encoded=$(url_encode "$path_id")
    escaped_title=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    # Locale properties (primary)
    curl -s -o /dev/null --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" \
        -d "[{\"key\":\"file.title\",\"value\":\"$escaped_title\"},{\"key\":\"title\",\"value\":\"$escaped_title\"}]" \
        "${REPO_FILES_URL}/${encoded}/localeProperties?locale=default" 2>/dev/null

    # Metadata fallback
    curl -s -o /dev/null --user "${USERNAME}:${PASSWORD}" -X PUT \
        -H "Content-Type: application/json" \
        -d "{\"stringKeyStringValueDto\":[{\"key\":\"file.title\",\"value\":\"$escaped_title\"}]}" \
        "${REPO_FILES_URL}/${encoded}/metadata" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEMP WORKSPACE & SPINNER
# ═══════════════════════════════════════════════════════════════════════════════

WORK_DIR=$(mktemp -d)
TMP_ZIP="${WORK_DIR}/export.zip"
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"

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
        kill "$spinner_pid" 2>/dev/null; wait "$spinner_pid" 2>/dev/null
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

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

info "Bidirectional content sync"
info "Local directory:  $LOCAL_DIR"
info "Repository path:  $REPO_PATH"
info "Server:           $PENTAHO_URL"
case "$PREFER" in
    local)  info "Conflict resolution: ${BOLD}prefer local${NC}" ;;
    server) info "Conflict resolution: ${BOLD}prefer server${NC}" ;;
    *)      info "Conflict resolution: ${BOLD}newer file wins${NC}" ;;
esac
[ "$DRY_RUN" = "true" ]    && info "Mode: DRY RUN — no changes will be made"
[ "$SMART_TITLE" = "true" ] && info "Smart title mode enabled"
echo ""

# ── Step 1: Download server content ─────────────────────────────────────────
PATH_ID=$(build_path_id "$REPO_PATH")
ENCODED_PATH_ID=$(url_encode "$PATH_ID")
DOWNLOAD_URL="${PENTAHO_URL}/api/repo/files/${ENCODED_PATH_ID}/download"

start_spinner "Downloading current server content..."

HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TMP_ZIP" \
    --user "${USERNAME}:${PASSWORD}" \
    --location --connect-timeout 10 --retry 3 --retry-delay 2 \
    "$DOWNLOAD_URL")

stop_spinner

SERVER_HAS_CONTENT="true"
if [ "$HTTP_CODE" -eq 404 ]; then
    info "Repository path does not exist yet — all local files will be pushed as new"
    SERVER_HAS_CONTENT="false"
elif [ "$HTTP_CODE" -ne 200 ]; then
    error "Failed to download server content (HTTP $HTTP_CODE)"
    [ -s "$TMP_ZIP" ] && { echo "Server response:"; head -c 500 "$TMP_ZIP"; echo ""; }
    exit 1
fi

CONTENT_ROOT=""
if [ "$SERVER_HAS_CONTENT" = "true" ]; then
    ZIP_BYTES=$(wc -c < "$TMP_ZIP" | tr -d ' ')
    info "Downloaded $ZIP_BYTES bytes from server"

    start_spinner "Extracting server content..."
    unzip -q -o "$TMP_ZIP" -d "$EXTRACT_DIR" || { stop_spinner; error "Extract failed"; exit 1; }
    stop_spinner

    SERVER_FILE_COUNT=$(find "$EXTRACT_DIR" -type f ! -name "exportManifest.xml" | wc -l | tr -d ' ')
    info "Extracted $SERVER_FILE_COUNT server files"

    find "$EXTRACT_DIR" -name "exportManifest.xml" -delete 2>/dev/null

    # Fetch true server timestamps from the tree API (timezone-independent epoch ms).
    # ZIP files store timestamps in the server's local time without timezone info,
    # so stat on extracted files is unreliable across timezones.
    SERVER_MTIME_INDEX="${WORK_DIR}/server_mtimes.txt"
    :> "$SERVER_MTIME_INDEX"
    TREE_PATH_ID=$(build_path_id "$REPO_PATH")
    TREE_ENCODED=$(url_encode "$TREE_PATH_ID")
    TREE_URL="${PENTAHO_URL}/api/repo/files/${TREE_ENCODED}/tree?depth=-1&showHidden=true&includeAcls=false"
    TREE_JSON="${WORK_DIR}/tree.json"
    curl -sS -o "$TREE_JSON" \
        --user "${USERNAME}:${PASSWORD}" \
        -H "Accept: application/json" \
        --connect-timeout 10 \
        "$TREE_URL" 2>/dev/null
    if [ -s "$TREE_JSON" ]; then
        TREE_JSON_PATH="$TREE_JSON" REPO_PREFIX="${REPO_PATH%/}/" python3 -c "
import json, sys, os
try:
    data = json.load(open(os.environ['TREE_JSON_PATH']))
except: sys.exit(0)
prefix = os.environ['REPO_PREFIX']
def walk(node):
    f = node.get('file', {})
    path = f.get('path', '')
    lm = f.get('lastModifiedDate', '')
    folder = f.get('folder', False)
    if not folder and path and lm:
        rel = path
        if rel.startswith(prefix):
            rel = rel[len(prefix):]
        elif rel.startswith('/'):
            rel = rel[1:]
        epoch_s = int(int(lm) / 1000)
        print(f'{rel}\t{epoch_s}')
    for child in node.get('children', []):
        walk(child)
walk(data)
" > "$SERVER_MTIME_INDEX" 2>/dev/null
        MTIME_COUNT=$(wc -l < "$SERVER_MTIME_INDEX" | tr -d ' ')
        info "Loaded $MTIME_COUNT server timestamps from API"
    fi

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

# ── Step 2: Setup ───────────────────────────────────────────────────────────
LOCAL_DIR_ABS="$(cd "$LOCAL_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_ROOT="${PROJECT_ROOT}/archive/content-backup/${TIMESTAMP}"

# ── Step 3: Build the unified file list ─────────────────────────────────────
# Bash 3.2 compatible (no associative arrays).
# Build sorted lists of relative paths, then use comm to classify.
LOCAL_LIST="${WORK_DIR}/local_files.txt"
SERVER_LIST="${WORK_DIR}/server_files.txt"
ALL_LIST="${WORK_DIR}/all_files.txt"

# Index local files (sorted, one per line)
:> "$LOCAL_LIST"
while IFS= read -r -d '' local_file; do
    rel_path="${local_file#"$LOCAL_DIR_ABS/"}"
    should_skip_file "$local_file" && continue
    echo "$rel_path" >> "$LOCAL_LIST"
done < <(find "$LOCAL_DIR_ABS" -type f -print0)
sort -o "$LOCAL_LIST" "$LOCAL_LIST"

# Index server files
:> "$SERVER_LIST"
if [ -n "$CONTENT_ROOT" ]; then
    while IFS= read -r -d '' server_file; do
        rel_path="${server_file#"$CONTENT_ROOT/"}"
        should_skip_file "$server_file" && continue
        echo "$rel_path" >> "$SERVER_LIST"
    done < <(find "$CONTENT_ROOT" -type f -print0)
fi
sort -o "$SERVER_LIST" "$SERVER_LIST"

# Classify using comm:
#   LOCAL_ONLY  = comm -23 (in local, not in server)
#   SERVER_ONLY = comm -13 (in server, not in local)
#   BOTH        = comm -12 (in both)
LOCAL_ONLY_LIST="${WORK_DIR}/local_only.txt"
SERVER_ONLY_LIST="${WORK_DIR}/server_only.txt"
BOTH_LIST="${WORK_DIR}/both.txt"

comm -23 "$LOCAL_LIST" "$SERVER_LIST" > "$LOCAL_ONLY_LIST"
comm -13 "$LOCAL_LIST" "$SERVER_LIST" > "$SERVER_ONLY_LIST"
comm -12 "$LOCAL_LIST" "$SERVER_LIST" > "$BOTH_LIST"

# Build a unified sorted list with state markers (tab-separated: state\tpath)
{
    sed 's/^/L\t/' "$LOCAL_ONLY_LIST"
    sed 's/^/S\t/' "$SERVER_ONLY_LIST"
    sed 's/^/B\t/' "$BOTH_LIST"
} | sort -t$'\t' -k2 > "$ALL_LIST"

TOTAL=$(wc -l < "$ALL_LIST" | tr -d ' ')
info "Analyzing $TOTAL unique files..."
if [ "$DRY_RUN" != "true" ]; then
    info "Backups will be saved to: archive/content-backup/$TIMESTAMP/"
fi
echo ""

# ── Step 4: Process each file ───────────────────────────────────────────────
PUSH_COUNT=0
PULL_COUNT=0
SKIP_COUNT=0
CONFLICT_COUNT=0
FAIL_COUNT=0

while IFS=$'\t' read -r state rel_path; do
    [ -z "$rel_path" ] && continue

    local_file="${LOCAL_DIR_ABS}/${rel_path}"
    server_file=""
    [ -n "$CONTENT_ROOT" ] && server_file="${CONTENT_ROOT}/${rel_path}"

    rel_dir=$(dirname "$rel_path")
    [ "$rel_dir" = "." ] && rel_dir=""
    if [ -z "$rel_dir" ]; then
        target_repo_dir="$REPO_PATH"
    else
        target_repo_dir="$REPO_PATH/$rel_dir"
    fi

    title=$(resolve_title "$local_file")

    # ── LOCAL_ONLY: push to server ──────────────────────────────────────
    if [ "$state" = "L" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            success "[PUSH  ↑]  $rel_path  (local only — will upload to server)"
            [ -n "$title" ] && detail "           title → $title"
        else
            if upload_single_file "$local_file" "$target_repo_dir" "$title"; then
                success "[PUSH  ↑]  $rel_path  (local only)"
                [ -n "$title" ] && detail "           title → $title"
            else
                error "[FAIL]     $rel_path"
                FAIL_COUNT=$((FAIL_COUNT + 1)); continue
            fi
        fi
        PUSH_COUNT=$((PUSH_COUNT + 1))
        continue
    fi

    # ── SERVER_ONLY: pull to local ──────────────────────────────────────
    if [ "$state" = "S" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            success "[PULL  ↓]  $rel_path  (server only — will download to local)"
        else
            mkdir -p "$(dirname "$local_file")"
            cp "$server_file" "$local_file"
            success "[PULL  ↓]  $rel_path  (server only)"
        fi
        PULL_COUNT=$((PULL_COUNT + 1))
        continue
    fi

    # ── BOTH: compare content ───────────────────────────────────────────
    if files_match "$local_file" "$server_file"; then
        detail "[SKIP  =]  $rel_path  (identical)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # ── CONFLICT: files differ ──────────────────────────────────────────
    CONFLICT_COUNT=$((CONFLICT_COUNT + 1))

    local_mtime=$(get_mtime "$local_file")
    server_mtime=$(get_server_mtime "$rel_path")
    local_time_str=$(format_time "$local_mtime")
    server_time_str=$(format_time "$server_mtime")

    # Determine winner
    winner=""
    reason=""

    case "$PREFER" in
        local)
            winner="local"
            reason="--prefer-local override"
            ;;
        server)
            winner="server"
            reason="--prefer-server override"
            ;;
        *)
            # Timestamp comparison
            if [ "$local_mtime" -gt "$server_mtime" ] 2>/dev/null; then
                winner="local"
                reason="local newer ($local_time_str vs server $server_time_str)"
            elif [ "$server_mtime" -gt "$local_mtime" ] 2>/dev/null; then
                winner="server"
                reason="server newer ($server_time_str vs local $local_time_str)"
            else
                # Identical timestamps or comparison failed — prefer local as tiebreaker
                winner="local"
                reason="same timestamp ($local_time_str) — defaulting to local"
            fi
            ;;
    esac

    backup_file="${BACKUP_ROOT}/${rel_path}"

    if [ "$winner" = "local" ]; then
        # Push local → server, archive server version
        if [ "$DRY_RUN" = "true" ]; then
            conflict "[PUSH  ↑]  $rel_path  (conflict: $reason)"
            detail "           archive server version → archive/content-backup/$TIMESTAMP/$rel_path"
            [ -n "$title" ] && detail "           title → $title"
        else
            mkdir -p "$(dirname "$backup_file")"
            cp "$server_file" "$backup_file"
            if upload_single_file "$local_file" "$target_repo_dir" "$title"; then
                conflict "[PUSH  ↑]  $rel_path  (conflict: $reason)"
                detail "           archived server version → archive/content-backup/$TIMESTAMP/$rel_path"
                [ -n "$title" ] && detail "           title → $title"
            else
                error "[FAIL]     $rel_path"
                FAIL_COUNT=$((FAIL_COUNT + 1)); continue
            fi
        fi
        PUSH_COUNT=$((PUSH_COUNT + 1))
    else
        # Pull server → local, archive local version
        if [ "$DRY_RUN" = "true" ]; then
            conflict "[PULL  ↓]  $rel_path  (conflict: $reason)"
            detail "           archive local version → archive/content-backup/$TIMESTAMP/$rel_path"
        else
            mkdir -p "$(dirname "$backup_file")"
            cp "$local_file" "$backup_file"
            cp "$server_file" "$local_file"
            conflict "[PULL  ↓]  $rel_path  (conflict: $reason)"
            detail "           archived local version → archive/content-backup/$TIMESTAMP/$rel_path"
        fi
        PULL_COUNT=$((PULL_COUNT + 1))
    fi

done < "$ALL_LIST"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${BOLD}  SYNC PLAN (DRY RUN)${NC}"
else
    echo -e "${BOLD}  SYNC SUMMARY${NC}"
fi
echo "────────────────────────────────────────────────────────────────"
echo "  Total files:    $TOTAL"
echo "  Pushed (↑):     $PUSH_COUNT"
echo "  Pulled (↓):     $PULL_COUNT"
echo "  Conflicts:      $CONFLICT_COUNT"
echo "  Identical (=):  $SKIP_COUNT"
echo "  Failed:         $FAIL_COUNT"
echo "════════════════════════════════════════════════════════════════"
if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — no changes were made. Run without --dry-run to execute."
fi

[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
