"""
Configuration — paths to script directories.

Uses environment variables when set (for remote deployment),
otherwise falls back to workspace-relative paths (local dev).
"""

import os
import shutil
from pathlib import Path
from typing import Optional

# Workspace root (parent of pentaho-ops-console/)
WORKSPACE_ROOT = Path(os.environ.get(
    "OPS_WORKSPACE_ROOT",
    str(Path(__file__).resolve().parent.parent.parent),
))

# Script directories
DEPLOY_SCRIPTS_DIR = Path(os.environ.get(
    "OPS_DEPLOY_SCRIPTS_DIR",
    str(WORKSPACE_ROOT / "pentaho-11-docker-deploy"),
))

MIGRATE_SCRIPTS_DIR = Path(os.environ.get(
    "OPS_MIGRATE_SCRIPTS_DIR",
    str(WORKSPACE_ROOT / "pdc-analysis" / "utility"),
))

PDC_AUTOMATION_SCRIPTS_DIR = Path(os.environ.get(
    "OPS_PDC_AUTOMATION_SCRIPTS_DIR",
    str(WORKSPACE_ROOT / "pdc-automation"),
))

# Content directory (used by migration upload commands)
CONTENT_DIR = WORKSPACE_ROOT / "pdc-analysis" / "content"

# Pentaho content snapshots directory
PENTAHO_CONTENT_DIR = WORKSPACE_ROOT / "pentaho-content"

# Analyzer schemas
ANALYZER_DIR = WORKSPACE_ROOT / "pdc-analysis" / "analyzer"

# ── Database ─────────────────────────────────────────────────────────────────

# Persistent data directory — outside the git-managed source tree so that
# `git reset --hard` on auto-update never wipes application data.
_OPS_CONSOLE_DIR = Path(__file__).resolve().parent.parent
_LEGACY_DATA_DIR = _OPS_CONSOLE_DIR / "data"
_DEFAULT_DATA_DIR = Path.home() / ".local" / "share" / "pentaho-ops-console"
DATA_DIR = Path(os.environ.get(
    "OPS_DATA_DIR",
    str(_DEFAULT_DATA_DIR),
))
DATA_DIR.mkdir(parents=True, exist_ok=True)

_DB_FILENAME = "ops-console.db"
_target_db = DATA_DIR / _DB_FILENAME
_legacy_db = _LEGACY_DATA_DIR / _DB_FILENAME
if DATA_DIR != _LEGACY_DATA_DIR and _legacy_db.exists() and not _target_db.exists():
    for suffix in ("", "-wal", "-shm"):
        src = _LEGACY_DATA_DIR / f"{_DB_FILENAME}{suffix}"
        if src.exists():
            shutil.copy2(src, DATA_DIR / src.name)

DATABASE_URL: str = os.environ.get(
    "OPS_DATABASE_URL",
    f"sqlite:///{_target_db}",
)

# ── Encryption ───────────────────────────────────────────────────────────────

# Optional Fernet key for encrypting secrets at rest.  Generate with:
#   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# If not set, secrets are stored as plaintext (a warning is logged).
ENCRYPTION_KEY: Optional[str] = os.environ.get("OPS_ENCRYPTION_KEY")
