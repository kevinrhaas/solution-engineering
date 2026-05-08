"""
Seed the database from existing on-disk files on first startup.

This is safe to call on every startup — upserts are idempotent.
"""

from __future__ import annotations
import logging
from datetime import datetime
from pathlib import Path

from ..config import DEPLOY_SCRIPTS_DIR
from .engine import get_db
from .models import Instance, Profile

logger = logging.getLogger(__name__)

# .env files live alongside the deploy scripts
_ENV_DIR = DEPLOY_SCRIPTS_DIR


def _parse_env_file(path: Path) -> dict[str, str]:
    """Parse a simple KEY=VALUE file, ignoring comments and blank lines."""
    result: dict[str, str] = {}
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            result[k.strip()] = v.strip()
    return result


def _server_type(cfg: dict[str, str]) -> str:
    kind = cfg.get("SERVER_TYPE", cfg.get("CLUSTER_TYPE", "")).lower()
    if "pdc" in kind:
        return "pdc"
    if "pentaho" in kind:
        return "pentaho"
    return ""


def _profile_name_for_state(state_path: Path, cfg: dict[str, str], env_names: list[str]) -> str:
    env_file = cfg.get("ENV_FILE", "")
    if env_file:
        return Path(env_file).stem

    stem = state_path.stem
    if stem.endswith("-runtime"):
        stem = stem[: -len("-runtime")]

    for env_name in sorted(env_names, key=len, reverse=True):
        if stem == env_name or stem.startswith(f"{env_name}-"):
            return env_name
    return stem


def seed_from_files() -> None:
    """Sync .env files and DB profiles on startup.

    The DB is authoritative when its record is newer than the file on disk —
    this means UI edits survive app updates that overwrite .env files.
    The file is authoritative when it is newer than the DB record (e.g. manual
    edits via SSH). DB profiles whose .env files are missing are restored.
    """
    if not _ENV_DIR.is_dir():
        logger.warning("Deploy scripts directory not found: %s — skipping seed", _ENV_DIR)
        return

    # ── Profiles ─────────────────────────────────────────────────────────────
    env_files = list(_ENV_DIR.glob("*.env"))
    env_names_on_disk = {p.stem for p in env_files}
    logger.info("Syncing %d on-disk profile(s) from %s", len(env_files), _ENV_DIR)

    with get_db() as db:
        db_profiles = {p.name: p for p in db.query(Profile).all()}

        for env_path in env_files:
            name = env_path.stem
            file_mtime = datetime.utcfromtimestamp(env_path.stat().st_mtime)
            existing = db_profiles.get(name)

            if existing is None:
                raw = env_path.read_text(errors="replace")
                cfg = _parse_env_file(env_path)
                db.add(Profile(name=name, server_type=_server_type(cfg), raw_env=raw))
                logger.debug("Seeded new profile from disk: %s", name)
            elif existing.updated_at > file_mtime:
                # DB record was saved after the file was last written — restore file
                env_path.write_text(existing.raw_env)
                logger.info("Restored %s.env from DB (DB updated %s > file mtime %s)",
                            name, existing.updated_at, file_mtime)
            else:
                # File is newer or equal — sync DB from file
                raw = env_path.read_text(errors="replace")
                cfg = _parse_env_file(env_path)
                existing.raw_env = raw
                existing.server_type = _server_type(cfg)
                existing.updated_at = datetime.utcnow()
                logger.debug("Updated DB from disk: %s", name)

        # Restore .env files for DB profiles that have no file on disk
        for name, profile in db_profiles.items():
            if name not in env_names_on_disk:
                env_path = _ENV_DIR / f"{name}.env"
                env_path.write_text(profile.raw_env)
                logger.info("Restored missing %s.env from DB", name)

    env_files = list(_ENV_DIR.glob("*.env"))  # refresh after any restores
    env_names = [p.stem for p in env_files]

    # ── Instances ────────────────────────────────────────────────────────────
    state_files = list(_ENV_DIR.glob("*-runtime.state"))
    logger.info("Seeding %d instance(s) from %s", len(state_files), _ENV_DIR)

    with get_db() as db:
        for state_path in state_files:
            sf_name = state_path.name
            raw = state_path.read_text(errors="replace")
            cfg = _parse_env_file(state_path)

            existing = db.query(Instance).filter_by(state_file=sf_name).first()
            profile_name = _profile_name_for_state(state_path, cfg, env_names)
            if existing is None:
                inst = Instance(
                    name=state_path.stem,
                    profile_name=cfg.get("PROFILE_NAME", profile_name),
                    state_file=sf_name,
                    ec2_instance_id=cfg.get("INSTANCE_ID", cfg.get("EC2_INSTANCE_ID", "")),
                    instance_ip=cfg.get("INSTANCE_IP", ""),
                    public_ip=cfg.get("PUBLIC_IP", ""),
                    instance_state=cfg.get("INSTANCE_STATE", ""),
                    deploy_phase=cfg.get("DEPLOY_PHASE", ""),
                    server_type=_server_type(cfg),
                    pentaho_version=cfg.get("PENTAHO_VERSION", ""),
                    pdc_version=cfg.get("PDC_VERSION", ""),
                    instance_type=cfg.get("INSTANCE_TYPE", ""),
                    environment=cfg.get("ENVIRONMENT", ""),
                    db_type=cfg.get("DB_TYPE", ""),
                    server_url=cfg.get("SERVER_URL", cfg.get("PDC_URL", "")),
                    created_date=cfg.get("CREATED_DATE", ""),
                    raw_state=raw,
                )
                db.add(inst)
                logger.debug("Seeded instance: %s", sf_name)
            else:
                # Update mutable fields only
                existing.profile_name = cfg.get("PROFILE_NAME", profile_name)
                existing.raw_state = raw
                existing.ec2_instance_id = cfg.get("INSTANCE_ID", cfg.get("EC2_INSTANCE_ID", ""))
                existing.instance_ip = cfg.get("INSTANCE_IP", "")
                existing.public_ip = cfg.get("PUBLIC_IP", "")
                existing.instance_state = cfg.get("INSTANCE_STATE", "")
                existing.deploy_phase = cfg.get("DEPLOY_PHASE", "")
                existing.server_url = cfg.get("SERVER_URL", cfg.get("PDC_URL", ""))
                existing.synced_at = datetime.utcnow()
