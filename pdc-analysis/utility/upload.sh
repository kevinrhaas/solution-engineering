#!/bin/bash

################################################################################
# upload.sh  (formerly push-file.sh)
#
# Uploads any file or a folder to Pentaho Server repository using REST API.
# For smart delta-sync of an entire directory, use push-content.sh instead.
#
# Usage:
#   ./upload.sh [--dry-run] [--include-markdown] [--title "Display Name"] [--smart-title] <file|folder> <repo-path> <server-ip> [username] [password]
#
# Parameters:
#   --dry-run   : Print actions without uploading
#   --include-markdown : Include *.md files when uploading folders
#   --title     : Set display title for the file in repository (optional)
#   --smart-title : Auto-generate title from filename (works for file and folder uploads)
#   file        : Path to the file to upload (any type)
#   folder      : Path to a folder to upload recursively
#   repo-path   : Target path in Pentaho repository (e.g., /public/data)
#   server-ip   : Pentaho server IP address or hostname
#   username    : Pentaho username (optional, defaults to 'admin')
#   password    : Pentaho password (optional, defaults to 'password')
#
# Examples:
#   ./upload.sh data.csv /public/data 192.168.1.100
#   ./upload.sh --title "Sample Job Console" sample-job-console.html /public/reports localhost
#   ./upload.sh --smart-title sample-job-console.html /public/reports localhost
#   ./upload.sh report.prpt /public/reports localhost admin mypassword
#   ./upload.sh cube.xml /public/analyzer 192.168.1.100
#   ./upload.sh ./pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 192.168.1.100
#   ./upload.sh --dry-run ./pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 192.168.1.100
#
# Note: This script only uploads files to the repository. For analyzer cubes
#       that need to be published, use push-cube.sh instead.
#
# Requirements:
#   - curl command must be available
#   - Valid Pentaho server credentials
#   - Network access to Pentaho server
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

# Validate minimum number of parameters
if [ $# -lt 3 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [--dry-run] [--include-markdown] [--title \"Display Name\"] [--smart-title] <file|folder> <repo-path> <server-ip> [username] [password]"
    echo ""
    echo "Parameters:"
    echo "  --dry-run  : Print actions without uploading"
    echo "  --include-markdown : Include *.md files when uploading folders"
    echo "  --title    : Set display title for the file in repository (optional)"
    echo "  --smart-title : Auto-generate title from filename (works for file and folder uploads)"
    echo "  file        : Path to the file to upload (any type)"
    echo "  folder      : Path to a folder to upload recursively"
    echo "  repo-path   : Target path in Pentaho repository (e.g., /public/data)"
    echo "  server-ip   : Pentaho server IP address or hostname"
    echo "  username    : Pentaho username (optional, defaults to 'admin')"
    echo "  password    : Pentaho password (optional, defaults to 'password')"
    echo ""
    echo "Examples:"
    echo "  $0 data.csv /public/data 192.168.1.100"
    echo "  $0 --title \"Sample Job Console\" sample-job-console.html /public/reports localhost"
    echo "  $0 --smart-title sample-job-console.html /public/reports localhost"
    echo "  $0 report.prpt /public/reports localhost admin mypassword"
    echo "  $0 ./pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 192.168.1.100"
    echo "  $0 --dry-run ./pdc-analysis/content/public/pdc-analysis /public/pdc-analysis 192.168.1.100"
    exit 1
fi

# Parse parameters
DRY_RUN="false"
FILE_TITLE=""
SMART_TITLE="false"
INCLUDE_MARKDOWN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --include-markdown)
            INCLUDE_MARKDOWN="true"
            shift
            ;;
        --title)
            FILE_TITLE="$2"
            shift 2
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

# Allow --title smart/auto as shorthand for smart title mode.
if [ "$FILE_TITLE" = "smart" ] || [ "$FILE_TITLE" = "auto" ]; then
    FILE_TITLE=""
    SMART_TITLE="true"
fi

FILE_PATH="$1"
REPO_PATH="$2"
SERVER_IP="$3"
USERNAME="${4:-admin}"
PASSWORD="${5:-password}"

# Strip quotes if present (handles Pentaho parameter edge cases)
FILE_PATH="${FILE_PATH%\"}"
FILE_PATH="${FILE_PATH#\"}"
REPO_PATH="${REPO_PATH%\"}"
REPO_PATH="${REPO_PATH#\"}"
SERVER_IP="${SERVER_IP%\"}"
SERVER_IP="${SERVER_IP#\"}"

# Validate input exists
if [ ! -e "$FILE_PATH" ]; then
    error "Path not found: $FILE_PATH"
    exit 1
fi

# Validate path is readable
if [ ! -r "$FILE_PATH" ]; then
    error "Path not readable: $FILE_PATH"
    exit 1
fi

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

info "Starting file upload..."
info "File: $FILE_PATH"
info "Target: $REPO_PATH"
info "Server: $PENTAHO_URL"

# Construct repository API URLs
REPO_FILES_URL="${PENTAHO_URL}/api/repo/files"
REPO_DIRS_URL="${PENTAHO_URL}/api/repo/dirs"

# Create temporary file for response
RESPONSE_FILE=$(mktemp)
HTTP_CODE_FILE=$(mktemp)
CURL_ERR_FILE=$(mktemp)

# Cleanup temp files on exit
trap "rm -f $RESPONSE_FILE $HTTP_CODE_FILE $CURL_ERR_FILE" EXIT

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
    local dir_id
    dir_id=$(build_path_id "$full_path")
    local encoded_dir_id
    encoded_dir_id=$(url_encode "$dir_id")
    local url="${REPO_FILES_URL}/${encoded_dir_id}"
    local code

    code=$(curl -sS -w "%{http_code}" -o /dev/null \
        --user "${USERNAME}:${PASSWORD}" \
        -X GET \
        2> "$CURL_ERR_FILE" \
        "$url")

    [ "$code" -eq 200 ]
}

ensure_repo_dir() {
    local full_path="$1"
    local trimmed="${full_path#/}"
    local current=""
    local root

    if [ -z "$trimmed" ]; then
        return 0
    fi

    IFS='/' read -r -a parts <<< "$trimmed"
    for part in "${parts[@]}"; do
        if [ -z "$part" ]; then
            continue
        fi
        if [ -z "$current" ]; then
            current="/$part"
        else
            current="$current/$part"
        fi
        if [ "$current" = "/public" ] || [ "$current" = "/home" ]; then
            mark_dir_cached "$current"
            continue
        fi
        if dir_cached "$current"; then
            continue
        fi

        if repo_dir_exists "$current"; then
            mark_dir_cached "$current"
            continue
        fi

        if [ "$DRY_RUN" = "true" ]; then
            info "Dry run: would create repo dir '$current'"
        else
            local dir_id
            dir_id=$(build_path_id "$current")
            local encoded_dir_id
            encoded_dir_id=$(url_encode "$dir_id")
            local url="${REPO_DIRS_URL}/${encoded_dir_id}"
            local code
            code=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
                --user "${USERNAME}:${PASSWORD}" \
                -X PUT \
                2> "$CURL_ERR_FILE" \
                "$url")

            if [ "$code" -ne 200 ] && [ "$code" -ne 201 ] && [ "$code" -ne 409 ]; then
                if ! repo_dir_exists "$current"; then
                    if [ "$code" = "000" ]; then
                        info "Directory create returned HTTP 000 for '$current'; continuing and letting upload verify path availability."
                        if [ -s "$CURL_ERR_FILE" ]; then
                            echo ""
                            echo "Curl error detail:"
                            cat "$CURL_ERR_FILE"
                        fi
                        mark_dir_cached "$current"
                        continue
                    fi
                    error "Failed to create repo dir '$current' (HTTP $code)"
                    if [ -s "$RESPONSE_FILE" ]; then
                        echo ""
                        echo "Server response:"
                        cat "$RESPONSE_FILE"
                    fi
                    if [ -s "$CURL_ERR_FILE" ]; then
                        echo ""
                        echo "Curl error detail:"
                        cat "$CURL_ERR_FILE"
                    fi
                    return 1
                fi
            fi
        fi
        mark_dir_cached "$current"
    done
    return 0
}
upload_file() {
    local source_file="$1"
    local target_dir="$2"
    local title="$3"
    local filename

    filename=$(basename "$source_file")

    info "Uploading file to Pentaho server..."
    info "File: $source_file"
    info "Target: $target_dir/$filename"
    if [ -n "$title" ]; then
        info "Title: $title"
    fi

    if ! ensure_repo_dir "$target_dir"; then
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: skipping upload"
        return 0
    fi

    local full_repo_path="${target_dir%/}/${filename}"
    local path_id
    path_id=$(build_path_id "$full_repo_path")
    local encoded_path_id
    encoded_path_id=$(url_encode "$path_id")
    local upload_url="${REPO_FILES_URL}/${encoded_path_id}?overwrite=true"

    HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${source_file}" \
        2> "$CURL_ERR_FILE" \
        "${upload_url}")

    echo "$HTTP_CODE" > "$HTTP_CODE_FILE"

    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
        success "File uploaded successfully!"
        success "Location: $target_dir/$filename"
        if [[ "$filename" == *.locale ]]; then
            if ! set_locale_hidden "$full_repo_path"; then
                return 1
            fi
        fi
        if [ -n "$title" ]; then
            if ! set_file_title "$full_repo_path" "$title"; then
                return 1
            fi
        fi
        return 0
    elif [ "$HTTP_CODE" -eq 401 ]; then
        error "Authentication failed. Please check username and password."
        error "HTTP Status: $HTTP_CODE"
    elif [ "$HTTP_CODE" -eq 403 ]; then
        error "Access denied. User '$USERNAME' does not have permission to upload to '$target_dir'"
        error "HTTP Status: $HTTP_CODE"
    elif [ "$HTTP_CODE" -eq 404 ]; then
        error "Server endpoint not found. Please check server URL: $PENTAHO_URL"
        error "HTTP Status: $HTTP_CODE"
    elif [ "$HTTP_CODE" -eq 500 ]; then
        error "Server error occurred during upload."
        error "HTTP Status: $HTTP_CODE"
    else
        error "Upload failed with HTTP status code: $HTTP_CODE"
        if [ "$HTTP_CODE" = "000" ] && [ -s "$CURL_ERR_FILE" ]; then
            echo ""
            echo "Curl error detail:"
            cat "$CURL_ERR_FILE"
        fi
    fi

    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    return 1
}

set_locale_hidden() {
    local repo_file_path="$1"
    local path_id
    path_id=$(build_path_id "$repo_file_path")
    local encoded_path_id
    encoded_path_id=$(url_encode "$path_id")
    local url="${REPO_FILES_URL}/${encoded_path_id}/metadata"
    local payload='{"stringKeyStringValueDto":[{"key":"_PERM_HIDDEN","value":"true"}]}'

    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would set _PERM_HIDDEN=true on '$repo_file_path'"
        return 0
    fi

    local code
    code=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")

    if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
        success "Marked hidden: $repo_file_path"
        return 0
    fi

    error "Failed to set metadata for '$repo_file_path' (HTTP $code)"
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    return 1
}

set_file_title() {
    local repo_file_path="$1"
    local title="$2"
    local path_id
    path_id=$(build_path_id "$repo_file_path")
    local encoded_path_id
    encoded_path_id=$(url_encode "$path_id")

    # Escape title for JSON (handle quotes, backslashes, newlines)
    local escaped_title
    escaped_title=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would set title='$title' on '$repo_file_path'"
        return 0
    fi

    # Set locale properties (title + file.title) — this is what the BA Server
    # user console displays. The localeProperties API expects a bare JSON array.
    local locale_url="${REPO_FILES_URL}/${encoded_path_id}/localeProperties?locale=default"
    local locale_payload="[{\"key\":\"file.title\",\"value\":\"$escaped_title\"},{\"key\":\"title\",\"value\":\"$escaped_title\"}]"

    local code
    code=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$locale_payload" \
        "$locale_url")

    # Also set metadata file.title as a fallback for files without locale support.
    local meta_url="${REPO_FILES_URL}/${encoded_path_id}/metadata"
    local meta_payload="{\"stringKeyStringValueDto\":[{\"key\":\"file.title\",\"value\":\"$escaped_title\"}]}"

    curl -s -w "%{http_code}" -o /dev/null \
        --user "${USERNAME}:${PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$meta_payload" \
        "$meta_url" > /dev/null 2>&1

    if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
        success "Set title '$title' on: $repo_file_path"
        return 0
    fi

    error "Failed to set title for '$repo_file_path' (HTTP $code)"
    if [ -s "$RESPONSE_FILE" ]; then
        echo ""
        echo "Server response:"
        cat "$RESPONSE_FILE"
    fi
    return 1
}

smart_title_from_filename() {
    local source_file="$1"
    local base_name
    local name_no_ext
    local normalized
    local title

    base_name=$(basename "$source_file")

    # Remove the last file extension.
    name_no_ext="${base_name%.*}"

    # Replace separators with spaces, collapse repeated spaces, trim ends.
    normalized=$(printf '%s' "$name_no_ext" | sed -E 's/[-_]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')

    # Title case each word.
    title=$(printf '%s' "$normalized" | awk '
        {
            for (i = 1; i <= NF; i++) {
                w = tolower($i)
                $i = toupper(substr(w,1,1)) substr(w,2)
            }
            print
        }
    ')

    printf '%s' "$title"
}

resolve_title_for_file() {
    local source_file="$1"
    local explicit_title="$2"

    if [ -n "$explicit_title" ]; then
        printf '%s' "$explicit_title"
        return 0
    fi

    if [ "$SMART_TITLE" = "true" ]; then
        smart_title_from_filename "$source_file"
        return 0
    fi

    printf '%s' ""
}

should_skip_file() {
    local source_file="$1"
    local base_name
    base_name=$(basename "$source_file")

    # Ignore hidden/system artifacts during folder uploads.
    if [[ "$base_name" == .* ]]; then
        return 0
    fi

    # Pentaho repository often rejects markdown attachments for these paths.
    if [ "$INCLUDE_MARKDOWN" != "true" ] && [[ "$base_name" == *.md ]]; then
        return 0
    fi

    return 1
}

if [ -f "$FILE_PATH" ]; then
    resolved_title=$(resolve_title_for_file "$FILE_PATH" "$FILE_TITLE")
    upload_file "$FILE_PATH" "$REPO_PATH" "$resolved_title"
    exit $?
fi

if [ ! -d "$FILE_PATH" ]; then
    error "Unsupported path type: $FILE_PATH"
    exit 1
fi

BASE_DIR="${FILE_PATH%/}"
info "Starting folder upload..."
info "Folder: $BASE_DIR"
info "Target: $REPO_PATH"
info "Server: $PENTAHO_URL"
if [ "$DRY_RUN" = "true" ]; then
    info "Dry run enabled"
fi
if [ -n "$FILE_TITLE" ]; then
    info "Folder upload will apply --title to every uploaded file"
fi
if [ "$SMART_TITLE" = "true" ]; then
    info "Smart title mode enabled (derived from each filename)"
fi

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

while IFS= read -r -d '' source_file; do
    if should_skip_file "$source_file"; then
        info "Skipping file: $source_file"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    rel_path="${source_file#"$BASE_DIR/"}"
    rel_dir=$(dirname "$rel_path")
    if [ "$rel_dir" = "." ]; then
        target_dir="$REPO_PATH"
    else
        target_dir="$REPO_PATH/$rel_dir"
    fi

    resolved_title=$(resolve_title_for_file "$source_file" "$FILE_TITLE")
    if upload_file "$source_file" "$target_dir" "$resolved_title"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < <(find "$BASE_DIR" -type f -print0)

if [ "$SUCCESS_COUNT" -eq 0 ] && [ "$FAIL_COUNT" -eq 0 ]; then
    error "No files found in folder: $BASE_DIR"
    exit 1
fi

info "Folder upload complete. Success: $SUCCESS_COUNT, Failed: $FAIL_COUNT, Skipped: $SKIP_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
