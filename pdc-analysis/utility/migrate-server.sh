#!/bin/bash

################################################################################
# migrate-server.sh
#
# Migrates Pentaho content and datasources from one server to another.
# Pulls everything from source, snapshots locally (optionally commits to git),
# then pushes to target.
#
# What is migrated:
#   - Repository content (reports, dashboards, .xanalyzer, .xdash, etc.)
#   - Home directory content (/home/* user files)
#   - Datasources: JDBC connections, Analysis/Mondrian schemas, DSW, Metadata
#
# What is NOT migrated:
#   - Server settings, LDAP/SSO config, email config
#   - Scheduled jobs/triggers
#   - User accounts & roles
#   - JNDI datasources (tomcat-level)
#   - Installed plugins & drivers
#
# Usage:
#   ./migrate-server.sh [flags] <source-server> <target-server> [username] [password]
#
# Flags:
#   --dry-run       : Show what would happen without making changes
#   --skip-content  : Skip repository content migration (datasources only)
#   --skip-home     : Skip /home directory content migration
#   --skip-ds       : Skip datasource migration (content only)
#   --no-git        : Skip git snapshot step
#   --content-path  : Repository path to migrate (default: / for everything)
#   --smart-title   : Auto-generate display titles on push
#
# Examples:
#   ./migrate-server.sh --dry-run 10.80.230.123:80 10.80.230.225:80
#   ./migrate-server.sh 10.80.230.123:80 10.80.230.225:80
#   ./migrate-server.sh --skip-ds 10.80.230.123:80 10.80.230.225:80 admin password
#   ./migrate-server.sh --content-path /public 10.80.230.123:80 10.80.230.225:80
#
# Requirements:
#   - curl, unzip
#   - git (optional, for snapshot commits)
#   - Scripts in same directory: pull-content.sh, push-content.sh,
#     pull-datasources.sh, push-datasources.sh,
#     pull-home-files.sh, push-home-files.sh
################################################################################

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

error()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
info()    { echo -e "${YELLOW}INFO: $1${NC}"; }
detail()  { echo -e "${CYAN}  $1${NC}"; }
header()  { echo -e "\n${BLUE}${BOLD}═══ $1 ═══${NC}\n"; }

# ═══════════════════════════════════════════════════════════════════════════════
# RESOLVE SCRIPT DIRECTORY
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENT_BASE_DIR="$(cd "$SCRIPT_DIR/../../pentaho-content" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

DRY_RUN="false"
SKIP_CONTENT="false"
SKIP_HOME="false"
SKIP_DS="false"
NO_GIT="false"
CONTENT_PATH="/public"
SMART_TITLE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN="true";        shift ;;
        --skip-content)   SKIP_CONTENT="true";   shift ;;
        --skip-home)      SKIP_HOME="true";      shift ;;
        --skip-ds)        SKIP_DS="true";        shift ;;
        --no-git)         NO_GIT="true";         shift ;;
        --smart-title)    SMART_TITLE="true";    shift ;;
        --content-path)   CONTENT_PATH="$2";     shift 2 ;;
        *)                break ;;
    esac
done

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    error "Invalid number of parameters"
    echo ""
    echo "Usage: $0 [flags] <source-server> <target-server> [username] [password]"
    echo ""
    echo "Flags:"
    echo "  --dry-run        Show plan without making changes"
    echo "  --skip-content   Skip repository content (datasources only)"
    echo "  --skip-home      Skip /home directory content"
    echo "  --skip-ds        Skip datasources (content only)"
    echo "  --no-git         Skip git snapshot step"
    echo "  --content-path   Repository path to migrate (default: /)"
    echo "  --smart-title    Auto-generate display titles on push"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run 10.80.230.123:80 10.80.230.225:80"
    echo "  $0 10.80.230.123:80 10.80.230.225:80"
    echo "  $0 --content-path /public 10.80.230.123:80 10.80.230.225:80 admin password"
    exit 1
fi

SOURCE_SERVER="$1"
TARGET_SERVER="$2"
USERNAME="${3:-admin}"
PASSWORD="${4:-password}"

# Extract IPs for directory naming (strip port)
SOURCE_IP="${SOURCE_SERVER%%:*}"
TARGET_IP="${TARGET_SERVER%%:*}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

# Snapshot directories
SOURCE_DIR="${CONTENT_BASE_DIR}/${SOURCE_IP}"
DS_DIR="${SOURCE_DIR}/datasources-${TIMESTAMP}"
CONTENT_DIR="${SOURCE_DIR}/content-${TIMESTAMP}"
HOME_DIR="${SOURCE_DIR}/home-${TIMESTAMP}"

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATE PREREQUISITES
# ═══════════════════════════════════════════════════════════════════════════════

for script in pull-content.sh push-content.sh pull-datasources.sh push-datasources.sh pull-home-files.sh push-home-files.sh; do
    if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
        error "Required script not found: ${SCRIPT_DIR}/${script}"
        exit 1
    fi
done

for cmd in curl unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd command not found. Please install $cmd."
        exit 1
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# SHOW PLAN
# ═══════════════════════════════════════════════════════════════════════════════

header "PENTAHO SERVER MIGRATION"
echo -e "  Source:        ${BOLD}${SOURCE_SERVER}${NC}"
echo -e "  Target:        ${BOLD}${TARGET_SERVER}${NC}"
echo -e "  Content path:  ${CONTENT_PATH}"
echo -e "  Username:      ${USERNAME}"
echo -e "  Timestamp:     ${TIMESTAMP}"
echo ""
echo -e "  Migrate content:     $([ "$SKIP_CONTENT" = "true" ] && echo "${RED}NO${NC}" || echo "${GREEN}YES${NC}")"
echo -e "  Migrate /home:       $([ "$SKIP_HOME" = "true" ] && echo "${RED}NO${NC}" || echo "${GREEN}YES${NC}")"
echo -e "  Migrate datasources: $([ "$SKIP_DS" = "true" ] && echo "${RED}NO${NC}" || echo "${GREEN}YES${NC}")"
echo -e "  Git snapshot:        $([ "$NO_GIT" = "true" ] && echo "${RED}NO${NC}" || echo "${GREEN}YES${NC}")"
if [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}>>> DRY RUN — no changes will be made <<<${NC}"
fi
echo ""

# Build common flags
DRY_RUN_FLAG=""
if [ "$DRY_RUN" = "true" ]; then
    DRY_RUN_FLAG="--dry-run"
fi

SMART_TITLE_FLAG=""
if [ "$SMART_TITLE" = "true" ]; then
    SMART_TITLE_FLAG="--smart-title"
fi

# Track overall status
ERRORS=0

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: PULL FROM SOURCE
# ═══════════════════════════════════════════════════════════════════════════════

header "PHASE 1: Pull from source (${SOURCE_SERVER})"

# --- Pull datasources ---
if [ "$SKIP_DS" != "true" ]; then
    info "Pulling datasources from ${SOURCE_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would pull datasources to: ${DS_DIR}"
        detail "Command: pull-datasources.sh --uncompress ${DS_DIR} ${SOURCE_SERVER} ${USERNAME} ****"
        echo ""
    else
        "${SCRIPT_DIR}/pull-datasources.sh" --uncompress "${DS_DIR}" "${SOURCE_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to pull datasources from ${SOURCE_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# --- Pull content ---
if [ "$SKIP_CONTENT" != "true" ]; then
    info "Pulling content from ${SOURCE_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would pull content to: ${CONTENT_DIR}"
        detail "Command: pull-content.sh --dry-run ${CONTENT_DIR} ${CONTENT_PATH} ${SOURCE_SERVER} ${USERNAME} ****"
        echo ""

        # Run with --dry-run to show what's there
        "${SCRIPT_DIR}/pull-content.sh" --dry-run "${CONTENT_DIR}" "${CONTENT_PATH}" "${SOURCE_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to pull content from ${SOURCE_SERVER}"
            ((ERRORS++))
        }
    else
        "${SCRIPT_DIR}/pull-content.sh" "${CONTENT_DIR}" "${CONTENT_PATH}" "${SOURCE_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to pull content from ${SOURCE_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# --- Pull /home content ---
if [ "$SKIP_HOME" != "true" ]; then
    info "Pulling /home content from ${SOURCE_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would pull /home content to: ${HOME_DIR}"
        detail "Command: pull-home-files.sh --dry-run ${HOME_DIR} /home ${SOURCE_SERVER} ${USERNAME} ****"
        echo ""

        bash "${SCRIPT_DIR}/pull-home-files.sh" --dry-run "${HOME_DIR}" "/home" "${SOURCE_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to list /home content from ${SOURCE_SERVER}"
            ((ERRORS++))
        }
    else
        bash "${SCRIPT_DIR}/pull-home-files.sh" "${HOME_DIR}" "/home" "${SOURCE_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to pull /home content from ${SOURCE_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: GIT SNAPSHOT
# ═══════════════════════════════════════════════════════════════════════════════

if [ "$NO_GIT" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    header "PHASE 2: Git snapshot"

    if command -v git &> /dev/null && git -C "$CONTENT_BASE_DIR" rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
        info "Creating git snapshot of pulled content..."
        (
            cd "$CONTENT_BASE_DIR"
            git add "${SOURCE_IP}/" 2>/dev/null || true
            if ! git diff --cached --quiet 2>/dev/null; then
                git commit -m "Snapshot ${SOURCE_IP} — datasources + content ${TIMESTAMP}" || {
                    error "Git commit failed"
                    ((ERRORS++))
                }
                success "Git snapshot committed"
            else
                info "No changes to commit"
            fi
        )
    else
        info "Not inside a git repository or git not available — skipping snapshot"
    fi
    echo ""
elif [ "$DRY_RUN" = "true" ] && [ "$NO_GIT" != "true" ]; then
    header "PHASE 2: Git snapshot"
    detail "Would commit pulled content to git"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3: PUSH TO TARGET
# ═══════════════════════════════════════════════════════════════════════════════

header "PHASE 3: Push to target (${TARGET_SERVER})"

# --- Push datasources ---
if [ "$SKIP_DS" != "true" ]; then
    info "Pushing datasources to ${TARGET_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would push datasources from: ${DS_DIR}"
        detail "Command: push-datasources.sh --dry-run ${DS_DIR} ${TARGET_SERVER} ${USERNAME} ****"
        echo ""

        # Only run dry-run push if we actually pulled something
        if [ -d "$DS_DIR" ]; then
            "${SCRIPT_DIR}/push-datasources.sh" --dry-run "${DS_DIR}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
                error "Dry-run push-datasources failed"
                ((ERRORS++))
            }
        else
            detail "No datasource directory yet (dry run pull doesn't create files)"
        fi
    else
        "${SCRIPT_DIR}/push-datasources.sh" "${DS_DIR}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to push datasources to ${TARGET_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# --- Push content ---
if [ "$SKIP_CONTENT" != "true" ]; then
    info "Pushing content to ${TARGET_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would push content from: ${CONTENT_DIR}"
        detail "Command: push-content.sh --dry-run ${SMART_TITLE_FLAG} ${CONTENT_DIR} ${CONTENT_PATH} ${TARGET_SERVER} ${USERNAME} ****"
        echo ""

        if [ -d "$CONTENT_DIR" ]; then
            "${SCRIPT_DIR}/push-content.sh" --dry-run ${SMART_TITLE_FLAG} "${CONTENT_DIR}" "${CONTENT_PATH}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
                error "Dry-run push-content failed"
                ((ERRORS++))
            }
        else
            detail "No content directory yet (dry run pull doesn't create files)"
        fi
    else
        "${SCRIPT_DIR}/push-content.sh" ${SMART_TITLE_FLAG} "${CONTENT_DIR}" "${CONTENT_PATH}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to push content to ${TARGET_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# --- Push /home content ---
if [ "$SKIP_HOME" != "true" ]; then
    info "Pushing /home content to ${TARGET_SERVER}..."
    if [ "$DRY_RUN" = "true" ]; then
        detail "Would push /home content from: ${HOME_DIR}"
        detail "Command: push-home-files.sh --dry-run ${HOME_DIR} ${TARGET_SERVER} ${USERNAME} ****"
        echo ""

        if [ -d "$HOME_DIR" ]; then
            bash "${SCRIPT_DIR}/push-home-files.sh" --dry-run "${HOME_DIR}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
                error "Dry-run push-home-files failed"
                ((ERRORS++))
            }
        else
            detail "No /home directory yet (dry run pull doesn't create files)"
        fi
    else
        bash "${SCRIPT_DIR}/push-home-files.sh" "${HOME_DIR}" "${TARGET_SERVER}" "${USERNAME}" "${PASSWORD}" || {
            error "Failed to push /home content to ${TARGET_SERVER}"
            ((ERRORS++))
        }
    fi
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

header "MIGRATION COMPLETE"

if [ "$DRY_RUN" = "true" ]; then
    info "This was a DRY RUN. No changes were made."
    echo ""
    echo -e "To execute for real, run:"
    echo -e "  ${BOLD}$0 ${SOURCE_SERVER} ${TARGET_SERVER} ${USERNAME} ****${NC}"
else
    if [ "$ERRORS" -gt 0 ]; then
        error "${ERRORS} error(s) occurred during migration. Review output above."
        exit 1
    else
        success "All operations completed successfully!"
        echo ""
        echo -e "  Datasources: ${DS_DIR}"
        echo -e "  Content:     ${CONTENT_DIR}"
        echo -e "  Home:        ${HOME_DIR}"
    fi
fi
