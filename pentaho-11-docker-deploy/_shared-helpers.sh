#!/bin/bash
# _shared-helpers.sh — Common functions for all deployment scripts
# Source this after setting SCRIPT_DIR and before using KEY_PATH or AWS CLI.

# ── Detect environment: local Mac vs remote server ───────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
    RUN_MODE="local"
else
    RUN_MODE="server"
fi

# ── Resolve KEY_PATH for the current environment ─────────────────────────────
resolve_key_path() {
    local kp="$1"
    if [ "$RUN_MODE" = "server" ] && [ ! -f "$kp" ]; then
        local fallback="$HOME/.ssh/$(basename "$kp")"
        if [ -f "$fallback" ]; then
            echo "$fallback"
            return
        fi
    fi
    echo "$kp"
}
