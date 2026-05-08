"""
Profiles API — CRUD for .env server profiles and reading .state files.
"""
from __future__ import annotations

import json
import logging
import tempfile
import re
import subprocess
import base64
import threading
import time
import urllib.request
import urllib.error
import urllib.parse
import uuid
import ssl
from urllib.parse import urlparse
from pathlib import Path

from datetime import datetime

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from ..config import DEPLOY_SCRIPTS_DIR, MIGRATE_SCRIPTS_DIR
from ..db.engine import get_db
from ..db.models import Instance, Profile

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/profiles", tags=["profiles"])

_SAFE_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')


def _env_files() -> list[Path]:
    """List all .env files in the deploy scripts directory, skipping macOS ._* files."""
    return sorted(p for p in DEPLOY_SCRIPTS_DIR.glob("*.env") if not p.name.startswith("._"))


def _parse_env_file(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'^export\s+', line)
        if m:
            line = line[m.end():]
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)', line)
        if m:
            result[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return result


def _parse_state_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    result = {}
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("if "):
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)', line)
        if m:
            result[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return result


def _detect_server_type(cfg: dict[str, str]) -> str:
    kind = cfg.get("SERVER_TYPE", cfg.get("CLUSTER_TYPE", "")).lower()
    if "pdc" in kind:
        return "pdc"
    if "pentaho" in kind:
        return "pentaho"
    return ""


def _profile_summary(env_path: Path) -> dict:
    env_data = _parse_env_file(env_path)
    state_path = _state_file_for(env_path)
    state_data = _parse_state_file(state_path)
    return {
        "name": env_path.stem,
        "filename": env_path.name,
        "pentaho_version": env_data.get("PENTAHO_VERSION", ""),
        "pdc_version": env_data.get("PDC_VERSION", ""),
        "instance_type": env_data.get("INSTANCE_TYPE", ""),
        "environment": env_data.get("ENVIRONMENT", ""),
        "instance_ip": state_data.get("PRIVATE_IP", "") or state_data.get("PUBLIC_IP", ""),
        "instance_id": state_data.get("INSTANCE_ID", ""),
        "instance_state": state_data.get("INSTANCE_STATE", ""),
        "deploy_phase": state_data.get("DEPLOY_PHASE", ""),
        "created_date": state_data.get("CREATED_DATE", ""),
        "state_file": state_path.name if state_data else "",
        "has_state": bool(state_data),
    }


def _profile_detail(profile_name: str) -> dict:
    env_path = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not env_path.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    env_data = _parse_env_file(env_path)
    state_path = _state_file_for(env_path)
    state_data = _parse_state_file(state_path)
    instance_paths = _state_files_for_profile(profile_name)
    return {
        "name": profile_name,
        "filename": env_path.name,
        "config": env_data,
        "state": state_data if state_data else None,
        "instances": [_instance_summary(path) for path in instance_paths],
        "raw": env_path.read_text(errors="replace"),
    }


# ── List ──────────────────────────────────────────────────────────────────────

@router.get("")
def list_profiles():
    return [_profile_summary(p) for p in _env_files()]


# ── Instances (all runtime.state files, including orphans) ────────────────────

def _state_files() -> list[Path]:
    """List all *-runtime.state files, skipping macOS ._* files."""
    return sorted(
        p for p in DEPLOY_SCRIPTS_DIR.glob("*-runtime.state")
        if not p.name.startswith("._")
    )


def _profile_name_for_state(state_path: Path, state_data: dict[str, str] | None = None) -> str:
    """Resolve the owning profile for a runtime state file.

    Newer state files may be named {profile}-{instance_id}-runtime.state, so
    simple suffix stripping is not enough. Prefer an explicit ENV_FILE, then
    match the longest known .env stem as a filename prefix.
    """
    state_data = state_data or _parse_state_file(state_path)
    env_file_field = state_data.get("ENV_FILE", "")
    if env_file_field:
        return Path(env_file_field).stem

    stem = state_path.stem
    if stem.endswith("-runtime"):
        stem = stem[: -len("-runtime")]

    env_stems = sorted((p.stem for p in _env_files()), key=len, reverse=True)
    for env_stem in env_stems:
        if stem == env_stem or stem.startswith(f"{env_stem}-"):
            return env_stem
    return stem


def _state_files_for_profile(profile_name: str) -> list[Path]:
    return [
        state_path for state_path in _state_files()
        if _profile_name_for_state(state_path) == profile_name
    ]


def _state_file_for(env_path: Path) -> Path:
    """Find the most recent runtime.state file for a profile."""
    matches = sorted(
        _state_files_for_profile(env_path.stem),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if matches:
        return matches[0]
    return env_path.parent / f"{env_path.stem}-runtime.state"


def _instance_summary(state_path: Path) -> dict:
    """Build an instance summary from a runtime.state file."""
    state_data = _parse_state_file(state_path)
    profile_name = _profile_name_for_state(state_path, state_data)

    env_path = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    has_profile = env_path.exists()
    # If there's a matching .env, pull version/type/environment from it
    env_data = _parse_env_file(env_path) if has_profile else {}

    # Build server URL and type
    deploy_phase = state_data.get("DEPLOY_PHASE", "")
    instance_ip = state_data.get("PRIVATE_IP", "") or state_data.get("PUBLIC_IP", "")
    pentaho_version = state_data.get("PENTAHO_VERSION", "") or env_data.get("PENTAHO_VERSION", "")
    pdc_version = state_data.get("PDC_VERSION", "") or env_data.get("PDC_VERSION", "")
    environment = env_data.get("ENVIRONMENT", "") or state_data.get("ENVIRONMENT", "")
    pentaho_phases = ("pentaho-deployed", "plugins-deployed")

    is_ops_console = environment == "ops-console" or "ops-console" in profile_name
    is_pdc = deploy_phase == "pdc-deployed" or bool(pdc_version) or "pdc" in profile_name.lower()
    is_pentaho = deploy_phase in pentaho_phases or (not deploy_phase and pentaho_version)

    if is_ops_console and instance_ip:
        server_type = "ops-console"
        server_url = f"http://{instance_ip}"
    elif is_pdc and instance_ip:
        server_type = "pdc"
        server_url = f"https://{instance_ip}"
    elif is_pentaho and instance_ip:
        server_type = "pentaho"
        server_url = f"http://{instance_ip}/pentaho/Login"
    elif instance_ip and not is_ops_console:
        # Unknown instance with an IP — assume Pentaho (health check will verify)
        server_type = "pentaho"
        server_url = f"http://{instance_ip}/pentaho/Login"
    else:
        server_type = ""
        server_url = ""

    return {
        "name": profile_name,
        "state_file": state_path.name,
        "instance_id": state_data.get("INSTANCE_ID", ""),
        "instance_ip": instance_ip,
        "instance_state": state_data.get("INSTANCE_STATE", ""),
        "created_date": state_data.get("CREATED_DATE", ""),
        "db_type": state_data.get("DB_TYPE", ""),
        "deploy_phase": deploy_phase,
        "pentaho_url": server_url if server_type == "pentaho" else "",
        "pentaho_version": pentaho_version,
        "pdc_version": pdc_version,
        "instance_type": env_data.get("INSTANCE_TYPE", ""),
        "environment": environment,
        "has_profile": has_profile,
        "server_url": server_url,
        "server_type": server_type,
    }


@router.get("/instances")
def list_instances():
    return [_instance_summary(p) for p in _state_files()]


# ── EC2 Discovery ─────────────────────────────────────────────────────────────

def _classify_aws_error(stderr: str) -> tuple[str, str]:
    """Classify an AWS CLI stderr message into a (code, friendly_message) tuple.

    Returns one of: 'auth_expired', 'auth_invalid', 'no_credentials', 'access_denied', 'other'.
    """
    s = (stderr or "").lower()
    if "expiredtoken" in s or "token included in the request is expired" in s:
        return ("auth_expired", "AWS session token has expired. Re-sync credentials in Config.")
    if "invalidclienttokenid" in s or "the security token included in the request is invalid" in s:
        return ("auth_invalid", "AWS credentials are invalid. Re-sync credentials in Config.")
    if "unable to locate credentials" in s or "could not connect to the endpoint url" in s and "credentials" in s:
        return ("no_credentials", "No AWS credentials configured. Add them in Config.")
    if "credentials" in s and ("not" in s or "missing" in s):
        return ("no_credentials", "AWS credentials missing or unreadable. Add them in Config.")
    if "accessdenied" in s or "unauthorizedoperation" in s or "is not authorized" in s:
        return ("access_denied", "AWS credentials lack permission to list EC2 instances.")
    if "could not connect" in s or "endpointconnectionerror" in s:
        return ("other", "Could not reach AWS — check network/region.")
    return ("other", stderr.strip().splitlines()[-1] if stderr.strip() else "AWS CLI failed.")


def _discover_ec2_instances() -> tuple[list[dict], dict | None]:
    """Call AWS CLI to list all running EC2 instances in the region.

    Returns (instances, error). error is None on success; otherwise a dict with
    'code', 'message', and optional 'detail'.
    """
    # Determine a working AWS profile from the .env files
    aws_profile = "default"
    aws_region = "us-west-2"
    for env_path in _env_files():
        env_data = _parse_env_file(env_path)
        if env_data.get("AWS_PROFILE"):
            aws_profile = env_data["AWS_PROFILE"]
            aws_region = env_data.get("AWS_REGION", aws_region)
            break

    cmd = [
        "aws", "ec2", "describe-instances",
        "--profile", aws_profile,
        "--region", aws_region,
        "--filters", "Name=instance-state-name,Values=running",
        "--query", "Reservations[].Instances[].{InstanceId:InstanceId,PrivateIpAddress:PrivateIpAddress,PublicIpAddress:PublicIpAddress,InstanceType:InstanceType,LaunchTime:LaunchTime,State:State.Name,Tags:Tags}",
        "--output", "json",
    ]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=15,
        )
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            logger.warning("aws ec2 describe-instances failed: %s", stderr)
            code, message = _classify_aws_error(stderr)
            return [], {
                "code": code,
                "message": message,
                "detail": stderr[-500:],
                "profile": aws_profile,
                "region": aws_region,
            }
        return json.loads(result.stdout), None
    except FileNotFoundError as exc:
        logger.warning("EC2 discovery error: %s", exc)
        return [], {"code": "other", "message": "AWS CLI not installed on the server.", "detail": str(exc)}
    except subprocess.TimeoutExpired as exc:
        logger.warning("EC2 discovery timeout: %s", exc)
        return [], {"code": "other", "message": "AWS CLI timed out.", "detail": str(exc)}
    except json.JSONDecodeError as exc:
        logger.warning("EC2 discovery parse error: %s", exc)
        return [], {"code": "other", "message": "Could not parse AWS CLI output.", "detail": str(exc)}


def _tags_to_dict(tags: list[dict] | None) -> dict[str, str]:
    """Convert AWS Tags [{Key:..., Value:...}] list to a dict."""
    if not tags:
        return {}
    return {t["Key"]: t["Value"] for t in tags if "Key" in t and "Value" in t}


@router.get("/instances/ec2")
def discover_ec2_instances():
    """Discover all running EC2 instances and merge with local state/profile data.

    Returns a list combining:
    - tracked instances (have a .state file and/or .env profile)
    - untracked instances (running in EC2 but no local state or profile)
    """
    # 1. Build the existing instances from state files
    tracked = [_instance_summary(p) for p in _state_files()]
    tracked_ips = {inst["instance_ip"] for inst in tracked if inst["instance_ip"]}
    tracked_ids = {inst["instance_id"] for inst in tracked if inst["instance_id"]}

    # 2. Discover from AWS
    ec2_instances, aws_error = _discover_ec2_instances()

    # 3. Enrich tracked instances with live EC2 data, and collect untracked ones
    untracked: list[dict] = []
    ec2_by_id: dict[str, dict] = {}
    ec2_by_ip: dict[str, dict] = {}
    for ec2 in ec2_instances:
        iid = ec2.get("InstanceId", "")
        ip = ec2.get("PrivateIpAddress", "")
        if iid:
            ec2_by_id[iid] = ec2
        if ip:
            ec2_by_ip[ip] = ec2

        # Check if this instance is already tracked
        if iid in tracked_ids or ip in tracked_ips:
            continue

        # Untracked instance — build a summary
        tags = _tags_to_dict(ec2.get("Tags"))
        name = tags.get("Name", "")
        untracked.append({
            "name": name or f"unknown-{ip or iid}",
            "state_file": "",
            "instance_id": iid,
            "instance_ip": ip,
            "public_ip": ec2.get("PublicIpAddress", ""),
            "instance_state": ec2.get("State", "unknown"),
            "created_date": ec2.get("LaunchTime", ""),
            "db_type": "",
            "deploy_phase": "",
            "pentaho_url": f"http://{ip}/pentaho/Login" if ip else "",
            "pentaho_version": "",
            "pdc_version": "",
            "instance_type": ec2.get("InstanceType", ""),
            "environment": "",
            "has_profile": False,
            "server_url": f"http://{ip}/pentaho/Login" if ip else "",
            "server_type": "unknown",
            "tracking_status": "untracked",
            "ec2_tags": tags,
        })

    # 4. Annotate tracked instances with "tracked" status and merge live instance type
    for inst in tracked:
        inst["tracking_status"] = "tracked"
        inst["ec2_tags"] = {}
        inst["public_ip"] = ""
        # Enrich with live EC2 data if available
        ec2 = ec2_by_id.get(inst["instance_id"]) or ec2_by_ip.get(inst["instance_ip"])
        if ec2:
            inst["instance_state"] = ec2.get("State", inst["instance_state"])
            if not inst["instance_type"]:
                inst["instance_type"] = ec2.get("InstanceType", "")
            inst["public_ip"] = ec2.get("PublicIpAddress", "")
            inst["ec2_tags"] = _tags_to_dict(ec2.get("Tags"))

    return {"tracked": tracked, "untracked": untracked, "aws_error": aws_error}


# ── Read ──────────────────────────────────────────────────────────────────────

@router.get("/{profile_name}")
def get_profile(profile_name: str):
    return _profile_detail(profile_name)


# ── Create ────────────────────────────────────────────────────────────────────

class ProfileCreate(BaseModel):
    name: str
    raw: str


@router.post("", status_code=201)
def create_profile(body: ProfileCreate):
    if not _SAFE_NAME.match(body.name):
        raise HTTPException(400, "Invalid profile name. Use alphanumeric, dots, hyphens, underscores.")
    env_path = DEPLOY_SCRIPTS_DIR / f"{body.name}.env"
    if env_path.exists():
        raise HTTPException(409, f"Profile already exists: {body.name}")
    env_path.write_text(body.raw)
    cfg = _parse_env_file(env_path)
    stype = _detect_server_type(cfg)
    with get_db() as db:
        existing = db.query(Profile).filter_by(name=body.name).first()
        if existing is None:
            db.add(Profile(name=body.name, server_type=stype, raw_env=body.raw))
        else:
            existing.raw_env = body.raw
            existing.server_type = stype
            existing.updated_at = datetime.utcnow()
    return _profile_detail(body.name)


# ── Duplicate ─────────────────────────────────────────────────────────────────

class ProfileDuplicate(BaseModel):
    new_name: str


@router.post("/{profile_name}/duplicate", status_code=201)
def duplicate_profile(profile_name: str, body: ProfileDuplicate):
    src = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not src.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    if not _SAFE_NAME.match(body.new_name):
        raise HTTPException(400, "Invalid profile name.")
    dst = DEPLOY_SCRIPTS_DIR / f"{body.new_name}.env"
    if dst.exists():
        raise HTTPException(409, f"Profile already exists: {body.new_name}")
    raw = src.read_text(errors="replace")
    dst.write_text(raw)
    cfg = _parse_env_file(dst)
    stype = _detect_server_type(cfg)
    with get_db() as db:
        existing = db.query(Profile).filter_by(name=body.new_name).first()
        if existing is None:
            db.add(Profile(name=body.new_name, server_type=stype, raw_env=raw))
        else:
            existing.raw_env = raw
            existing.server_type = stype
            existing.updated_at = datetime.utcnow()
    return _profile_detail(body.new_name)


# ── Rename ────────────────────────────────────────────────────────────────────

class ProfileRename(BaseModel):
    new_name: str


def _rename_state_filename(state_path: Path, old_name: str, new_name: str) -> Path:
    """Rename state filename prefix from old profile name to new profile name."""
    old_prefix = f"{old_name}-"
    if state_path.name == f"{old_name}-runtime.state":
        return state_path.with_name(f"{new_name}-runtime.state")
    if state_path.name.startswith(old_prefix):
        return state_path.with_name(f"{new_name}{state_path.name[len(old_name):]}")
    return state_path


def _rewrite_state_profile_refs(path: Path, old_name: str, new_name: str):
    """Update profile references inside a runtime state file."""
    lines_out: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line.strip())
        if not m:
            lines_out.append(line)
            continue
        key = m.group(1)
        raw_val = m.group(2).strip().strip('"').strip("'")
        if key == "ENV_FILE":
            line = f"ENV_FILE={new_name}.env"
        elif key == "PROFILE_NAME" and raw_val == old_name:
            line = f"PROFILE_NAME={new_name}"
        lines_out.append(line)
    path.write_text("\n".join(lines_out) + "\n")


@router.put("/{profile_name}/rename")
def rename_profile(profile_name: str, body: ProfileRename):
    if not _SAFE_NAME.match(body.new_name):
        raise HTTPException(400, "Invalid profile name.")
    if body.new_name == profile_name:
        raise HTTPException(400, "New profile name must be different from current name.")

    src_env = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not src_env.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")

    dst_env = DEPLOY_SCRIPTS_DIR / f"{body.new_name}.env"
    if dst_env.exists():
        raise HTTPException(409, f"Profile already exists: {body.new_name}")

    state_files = _state_files_for_profile(profile_name)
    planned_state_moves: list[tuple[Path, Path]] = [
        (p, _rename_state_filename(p, profile_name, body.new_name)) for p in state_files
    ]
    for src_state, dst_state in planned_state_moves:
        if src_state != dst_state and dst_state.exists():
            raise HTTPException(409, f"State file already exists: {dst_state.name}")

    moved_states: list[tuple[Path, Path]] = []
    env_renamed = False
    try:
        src_env.rename(dst_env)
        env_renamed = True

        for src_state, dst_state in planned_state_moves:
            if src_state != dst_state:
                src_state.rename(dst_state)
            _rewrite_state_profile_refs(dst_state, profile_name, body.new_name)
            moved_states.append((src_state, dst_state))
    except OSError as exc:
        # Best-effort rollback for filesystem operations.
        for src_state, dst_state in reversed(moved_states):
            if src_state != dst_state and dst_state.exists() and not src_state.exists():
                try:
                    dst_state.rename(src_state)
                except OSError:
                    pass
        if env_renamed and dst_env.exists() and not src_env.exists():
            try:
                dst_env.rename(src_env)
            except OSError:
                pass
        raise HTTPException(500, f"Could not rename profile files: {exc}")

    with get_db() as db:
        profile = db.query(Profile).filter_by(name=profile_name).first()
        if profile:
            profile.name = body.new_name
            profile.updated_at = datetime.utcnow()

        db.query(Instance).filter_by(profile_name=profile_name).update(
            {"profile_name": body.new_name, "name": body.new_name, "synced_at": datetime.utcnow()},
            synchronize_session=False,
        )

    return _profile_detail(body.new_name)


# ── Update ────────────────────────────────────────────────────────────────────

class ProfileUpdate(BaseModel):
    raw: str


@router.put("/{profile_name}")
def update_profile(profile_name: str, body: ProfileUpdate):
    env_path = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not env_path.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    env_path.write_text(body.raw)
    cfg = _parse_env_file(env_path)
    stype = _detect_server_type(cfg)
    with get_db() as db:
        profile = db.query(Profile).filter_by(name=profile_name).first()
        if profile:
            profile.raw_env = body.raw
            profile.server_type = stype
            profile.updated_at = datetime.utcnow()
        else:
            db.add(Profile(name=profile_name, server_type=stype, raw_env=body.raw))
    return _profile_detail(profile_name)


# ── Delete ────────────────────────────────────────────────────────────────────

@router.delete("/instances/{state_file}")
def delete_instance(state_file: str):
    """Delete an instance's runtime state file."""
    if not _SAFE_NAME.match(state_file):
        raise HTTPException(400, "Invalid state file name.")
    state_path = DEPLOY_SCRIPTS_DIR / state_file
    if not state_path.exists():
        raise HTTPException(404, f"State file not found: {state_file}")
    state_path.unlink()
    return {"status": "deleted", "state_file": state_file}


@router.delete("/{profile_name}")
def delete_profile(profile_name: str):
    env_path = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not env_path.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    env_path.unlink()
    with get_db() as db:
        profile = db.query(Profile).filter_by(name=profile_name).first()
        if profile:
            db.delete(profile)
    return {"status": "deleted", "name": profile_name}


# ── Health Check ──────────────────────────────────────────────────────────────

_IP_RE = re.compile(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')

_REPORTS_LOCK = threading.Lock()
_CONTENT_REPORTS: dict[str, dict] = {}


def _utc_now() -> float:
    return time.time()


def _set_report(report_id: str, **fields):
    with _REPORTS_LOCK:
        if report_id in _CONTENT_REPORTS:
            _CONTENT_REPORTS[report_id].update(fields)


def _append_report_log(report_id: str, line: str):
    with _REPORTS_LOCK:
        report = _CONTENT_REPORTS.get(report_id)
        if not report:
            return
        logs = report.setdefault("logs", [])
        logs.append({"ts": _utc_now(), "text": line})
        # Keep payload bounded
        if len(logs) > 300:
            del logs[: len(logs) - 300]


def _run_cmd(cmd: list[str], cwd: Path, timeout_s: int = 180) -> tuple[int, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(cwd), timeout=timeout_s)
    combined = "\n".join([result.stdout or "", result.stderr or ""]).strip()
    return result.returncode, combined


def _scan_file_tree(root: Path) -> tuple[list[dict], dict[str, int], int]:
    files: list[dict] = []
    ext_counts: dict[str, int] = {}
    total_bytes = 0
    if not root.exists():
        return files, ext_counts, total_bytes
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root))
        size = p.stat().st_size
        total_bytes += size
        ext = p.suffix.lower() if p.suffix else "(no-ext)"
        ext_counts[ext] = ext_counts.get(ext, 0) + 1
        files.append({"path": rel, "size": size, "ext": ext})
    return files, ext_counts, total_bytes


def _read_text_safe(path: Path, max_len: int = 500_000) -> str:
    try:
        data = path.read_text(errors="replace")
    except OSError:
        return ""
    if len(data) > max_len:
        return data[:max_len]
    return data


def _extract_mondrian_catalogs(analysis_dir: Path) -> list[dict]:
    catalogs: list[dict] = []
    if not analysis_dir.exists():
        return catalogs
    schema_name_re = re.compile(r'<Schema\s+[^>]*name="([^"]+)"', re.IGNORECASE)
    cube_name_re = re.compile(r'<Cube\s+[^>]*name="([^"]+)"', re.IGNORECASE)
    for xml_file in sorted(analysis_dir.glob("*.xml")):
        text = _read_text_safe(xml_file)
        schema_name = ""
        m = schema_name_re.search(text)
        if m:
            schema_name = m.group(1)
        cubes = cube_name_re.findall(text)
        catalogs.append({
            "file": xml_file.name,
            "schema": schema_name,
            "cube_count": len(cubes),
            "cubes": cubes,
        })
    return catalogs


def _parse_home_summary(log_text: str) -> dict:
    totals = {"total": 0, "downloaded": 0, "failed": 0, "skipped": 0}
    for line in (log_text or "").splitlines():
        m = re.search(r"Total:\s*(\d+)", line)
        if m:
            totals["total"] = int(m.group(1))
        m = re.search(r"Downloaded:\s*(\d+)", line)
        if m:
            totals["downloaded"] = int(m.group(1))
        m = re.search(r"Failed:\s*(\d+)", line)
        if m:
            totals["failed"] = int(m.group(1))
        m = re.search(r"Skipped:\s*(\d+)", line)
        if m:
            totals["skipped"] = int(m.group(1))
    return totals


def _normalize_server_for_scripts(server_url: str) -> tuple[str, str]:
    """Return (base_url, host_port) for migrate utility scripts.

    Scripts expect host:port (no scheme, no path).
    """
    parsed = urlparse(server_url)
    host = parsed.hostname or ""
    if not host:
        raise ValueError(f"Invalid server URL: {server_url}")
    scheme = parsed.scheme or "http"
    port = parsed.port
    if not port:
        port = 443 if scheme == "https" else 80
    return f"{scheme}://{host}:{port}", f"{host}:{port}"


def _build_pentaho_auth_header(username: str, password: str) -> dict[str, str]:
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    return {
        "Authorization": f"Basic {token}",
        "Accept": "application/json",
    }


def _build_repo_path_id(path: str) -> str:
    path = (path or "/").strip()
    if not path.startswith("/"):
        path = "/" + path
    path = path.rstrip("/")
    path = path[1:]
    if not path:
        return ":"
    return ":" + path.replace("/", ":")


def _list_repo_tree(
    report_id: str,
    pentaho_base_url: str,
    username: str,
    password: str,
    repo_root: str,
    phase: str,
    start_progress: int,
    end_progress: int,
    max_items: int = 4000,
) -> dict:
    """Recursively list Pentaho repository entries via /api/repo/files/{id}/children."""
    headers = _build_pentaho_auth_header(username, password)
    queue = [repo_root]
    visited = set()
    items: list[dict] = []
    ext_counts: dict[str, int] = {}
    file_count = 0
    dir_count = 0

    while queue and len(items) < max_items:
        current = queue.pop(0)
        if current in visited:
            continue
        visited.add(current)

        path_id = _build_repo_path_id(current)
        encoded = urllib.parse.quote(path_id, safe="")
        url = f"{pentaho_base_url}/api/repo/files/{encoded}/children"
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                payload = json.loads(resp.read().decode("utf-8", errors="replace"))
        except urllib.error.HTTPError as err:
            body = err.read(3000).decode("utf-8", errors="replace")
            raise RuntimeError(f"Failed listing {current}: HTTP {err.code} {body[:500]}")
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"Failed listing {current}: {exc}")

        entries = payload.get("repositoryFileDto", [])
        if entries is None:
            entries = []
        if isinstance(entries, dict):
            entries = [entries]

        for entry in entries:
            entry_path = entry.get("path") or ""
            is_folder = bool(entry.get("folder"))
            entry_size = entry.get("fileSize")
            if entry_size is None:
                entry_size = 0

            if is_folder:
                dir_count += 1
                ext = "(dir)"
                if entry_path and entry_path not in visited:
                    queue.append(entry_path)
            else:
                file_count += 1
                suffix = Path(entry_path).suffix.lower() if entry_path else ""
                ext = suffix if suffix else "(no-ext)"
            ext_counts[ext] = ext_counts.get(ext, 0) + 1
            items.append(
                {
                    "path": entry_path,
                    "name": entry.get("name", ""),
                    "folder": is_folder,
                    "size": int(entry_size) if isinstance(entry_size, int | float) else 0,
                    "ext": ext,
                }
            )
            if len(items) >= max_items:
                break

        # Progress climbs steadily while scanning.
        span = max(1, end_progress - start_progress)
        step = min(span, len(visited))
        _set_report(
            report_id,
            phase=phase,
            progress=start_progress + step,
            message=f"Scanning {repo_root} ({file_count} files, {dir_count} folders discovered)",
        )

    return {
        "items": items,
        "ext_counts": ext_counts,
        "file_count": file_count,
        "dir_count": dir_count,
        "truncated": len(items) >= max_items,
    }


def _probe_url(url: str, timeout_s: int = 10) -> dict:
    req = urllib.request.Request(url, method="GET")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    try:
        with opener.open(req, timeout=timeout_s) as resp:
            body = resp.read(3000)
            ctype = resp.headers.get("Content-Type", "")
            return {
                "url": url,
                "ok": True,
                "status": resp.status,
                "content_type": ctype,
                "body_preview": body.decode("utf-8", errors="replace"),
            }
    except urllib.error.HTTPError as err:
        body = err.read(3000)
        return {
            "url": url,
            "ok": False,
            "status": err.code,
            "content_type": err.headers.get("Content-Type", "") if err.headers else "",
            "body_preview": body.decode("utf-8", errors="replace"),
        }
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        return {
            "url": url,
            "ok": False,
            "status": None,
            "content_type": "",
            "body_preview": str(exc),
        }


def _collect_pentaho_report(report_id: str, server_url: str, username: str, password: str) -> dict:
    base_url, host_port = _normalize_server_for_scripts(server_url)
    tmp_root = Path(tempfile.mkdtemp(prefix="ops-content-preview-"))
    ds_dir = tmp_root / "datasources"
    ds_dir.mkdir(parents=True, exist_ok=True)

    try:
        pentaho_base = f"{base_url}/pentaho"

        _set_report(report_id, phase="content", progress=8, message="Scanning Pentaho repository content")
        _append_report_log(report_id, f"Target: {base_url}")
        content_scan = _list_repo_tree(
            report_id=report_id,
            pentaho_base_url=pentaho_base,
            username=username,
            password=password,
            repo_root="/",
            phase="content",
            start_progress=8,
            end_progress=34,
            max_items=5000,
        )

        _set_report(report_id, phase="home", progress=35, message="Scanning /home tree")
        try:
            home_scan = _list_repo_tree(
                report_id=report_id,
                pentaho_base_url=pentaho_base,
                username=username,
                password=password,
                repo_root="/home",
                phase="home",
                start_progress=35,
                end_progress=54,
                max_items=2500,
            )
        except Exception as exc:
            _append_report_log(report_id, f"/home scan unavailable: {exc}")
            home_scan = {
                "items": [],
                "ext_counts": {},
                "file_count": 0,
                "dir_count": 0,
                "truncated": False,
            }

        _set_report(report_id, phase="datasources", progress=55, message="Pulling datasources and Mondrian catalogs")
        ds_error = ""
        rc, ds_out = _run_cmd(
            ["bash", str(MIGRATE_SCRIPTS_DIR / "pull-datasources.sh"), "--uncompress", str(ds_dir), host_port, username, password],
            cwd=MIGRATE_SCRIPTS_DIR,
            timeout_s=150,
        )
        if rc != 0:
            ds_error = (ds_out or "")[-900:]
            _append_report_log(report_id, "Datasource pull failed; continuing with repository/home inventory")

        _set_report(report_id, phase="analyze", progress=82, message="Analyzing collected artifacts")

        ds_files, ds_exts, ds_bytes = _scan_file_tree(ds_dir)

        analysis_dir = ds_dir / "analysis"
        jdbc_dir = ds_dir / "jdbc"
        dsw_dir = ds_dir / "dsw"
        metadata_dir = ds_dir / "metadata"

        mondrian_catalogs = _extract_mondrian_catalogs(analysis_dir)

        def top_n(items: dict[str, int], n: int = 12):
            return [{"name": k, "count": v} for k, v in sorted(items.items(), key=lambda x: x[1], reverse=True)[:n]]

        content_items = content_scan["items"]
        home_items = home_scan["items"]
        content_exts = content_scan["ext_counts"]
        home_exts = home_scan["ext_counts"]

        content_files = [i for i in content_items if not i.get("folder")]
        home_files = [i for i in home_items if not i.get("folder")]
        content_bytes = sum(int(i.get("size", 0) or 0) for i in content_files)
        home_bytes = sum(int(i.get("size", 0) or 0) for i in home_files)

        home_summary = {
            "total_files": len(home_files),
            "total_folders": home_scan["dir_count"],
            "total_bytes": home_bytes,
            "truncated": home_scan["truncated"],
            "ext_breakdown": top_n(home_exts),
        }

        return {
            "kind": "pentaho",
            "target": base_url,
            "summary": {
                "content_files": len(content_files),
                "content_folders": content_scan["dir_count"],
                "content_bytes": content_bytes,
                "datasource_files": len(ds_files),
                "datasource_bytes": ds_bytes,
                "mondrian_catalogs": len(mondrian_catalogs),
                "home_total_files": home_summary["total_files"],
            },
            "navigator": [
                {"id": "overview", "label": "Overview"},
                {"id": "content", "label": "Repository Content"},
                {"id": "datasources", "label": "Datasources"},
                {"id": "mondrian", "label": "Mondrian"},
                {"id": "home", "label": "/home Scan"},
                {"id": "raw", "label": "Raw Logs"},
            ],
            "sections": {
                "content": {
                    "path": "/",
                    "ext_breakdown": top_n(content_exts),
                    "truncated": content_scan["truncated"],
                    "items": content_items[:1800],
                },
                "datasources": {
                    "ext_breakdown": top_n(ds_exts),
                    "pull_error": ds_error,
                    "counts": {
                        "analysis_xml": len(list(analysis_dir.glob("*.xml"))) if analysis_dir.exists() else 0,
                        "jdbc_json": len(list(jdbc_dir.glob("*.json"))) if jdbc_dir.exists() else 0,
                        "dsw_files": len(list(dsw_dir.glob("*"))) if dsw_dir.exists() else 0,
                        "metadata_files": len(list(metadata_dir.glob("*"))) if metadata_dir.exists() else 0,
                    },
                    "items": ds_files[:1200],
                },
                "mondrian": {
                    "catalogs": mondrian_catalogs,
                },
                "home": {
                    "scan_summary": home_summary,
                    "items": home_items[:1200],
                },
            },
        }
    finally:
        try:
            for p in tmp_root.rglob("*"):
                if p.is_file():
                    p.unlink(missing_ok=True)
            for p in sorted(tmp_root.rglob("*"), reverse=True):
                if p.is_dir():
                    p.rmdir()
            tmp_root.rmdir()
        except OSError:
            pass


def _collect_pdc_report(report_id: str, server_url: str) -> dict:
    parsed = urlparse(server_url)
    host = parsed.hostname or ""
    scheme = parsed.scheme or "https"
    port = parsed.port or (443 if scheme == "https" else 80)
    base = f"{scheme}://{host}:{port}"

    _set_report(report_id, phase="probe", progress=20, message="Probing PDC endpoints")
    endpoints = [
        "/",
        "/api/health",
        "/api",
        "/openapi.json",
        "/swagger",
        "/v1",
        "/pdc",
    ]
    probes = []
    for idx, ep in enumerate(endpoints):
        probes.append(_probe_url(f"{base}{ep}"))
        _set_report(report_id, progress=20 + int((idx + 1) * 55 / len(endpoints)))

    _set_report(report_id, phase="analyze", progress=82, message="Analyzing PDC probe results")
    ok_count = sum(1 for p in probes if p.get("ok"))
    status_counts: dict[str, int] = {}
    for p in probes:
        k = str(p.get("status"))
        status_counts[k] = status_counts.get(k, 0) + 1

    # Extract quick hints from body text
    markers = {
        "pentaho": 0,
        "pdc": 0,
        "openapi": 0,
        "json": 0,
    }
    for p in probes:
        body = (p.get("body_preview") or "").lower()
        if "pentaho" in body:
            markers["pentaho"] += 1
        if "pdc" in body:
            markers["pdc"] += 1
        if "openapi" in body or "swagger" in body:
            markers["openapi"] += 1
        if body.startswith("{") or "application/json" in (p.get("content_type") or ""):
            markers["json"] += 1

    return {
        "kind": "pdc",
        "target": base,
        "summary": {
            "probed_endpoints": len(probes),
            "reachable_endpoints": ok_count,
            "status_breakdown": status_counts,
        },
        "navigator": [
            {"id": "overview", "label": "Overview"},
            {"id": "probes", "label": "Endpoint Probes"},
            {"id": "signals", "label": "Signals"},
            {"id": "raw", "label": "Raw Logs"},
        ],
        "sections": {
            "probes": {"items": probes},
            "signals": {"markers": markers},
        },
    }


class ContentPreviewRequest(BaseModel):
    server_url: str
    server_type: str = ""
    username: str = "admin"
    password: str = "password"
    instance_name: str = ""


def _run_content_preview(report_id: str, req: ContentPreviewRequest):
    try:
        _set_report(report_id, status="running", phase="detect", progress=5, message="Detecting server type")
        st = (req.server_type or "").strip().lower()
        if st not in {"pentaho", "pdc"}:
            if "/pentaho" in req.server_url.lower():
                st = "pentaho"
            elif req.server_url.lower().startswith("https://"):
                st = "pdc"
            else:
                st = "pentaho"

        _append_report_log(report_id, f"Server type: {st}")
        if st == "pentaho":
            report = _collect_pentaho_report(report_id, req.server_url, req.username, req.password)
        else:
            report = _collect_pdc_report(report_id, req.server_url)

        _set_report(
            report_id,
            status="completed",
            phase="done",
            progress=100,
            message="Content preview complete",
            finished_at=_utc_now(),
            report=report,
        )
    except Exception as exc:
        _append_report_log(report_id, f"Error: {exc}")
        _set_report(
            report_id,
            status="failed",
            phase="failed",
            progress=100,
            message="Content preview failed",
            error=str(exc),
            finished_at=_utc_now(),
        )


@router.post("/instances/content-preview/start")
def start_content_preview(req: ContentPreviewRequest):
    report_id = uuid.uuid4().hex[:12]
    with _REPORTS_LOCK:
        _CONTENT_REPORTS[report_id] = {
            "id": report_id,
            "status": "pending",
            "phase": "queued",
            "progress": 0,
            "message": "Queued",
            "error": "",
            "instance_name": req.instance_name,
            "server_url": req.server_url,
            "server_type": req.server_type,
            "started_at": _utc_now(),
            "finished_at": None,
            "report": None,
            "logs": [],
        }

    thread = threading.Thread(target=_run_content_preview, args=(report_id, req), daemon=True)
    thread.start()
    return {"report_id": report_id}


@router.get("/instances/content-preview/{report_id}")
def get_content_preview(report_id: str):
    with _REPORTS_LOCK:
        report = _CONTENT_REPORTS.get(report_id)
        if not report:
            raise HTTPException(404, "Content preview report not found")
        return report


@router.get("/instances/health")
def check_instance_health(url: str = Query(..., description="URL to check")):
    """Check if a server URL is reachable.

    Reachability means the host/service responded over HTTP(S), even if the
    response is an auth or error code (401/403/404/etc). Connection, DNS, TLS,
    and timeout failures are treated as unreachable.
    """
    # Validate the URL is a safe internal HTTP/HTTPS URL
    if not url.startswith("http://") and not url.startswith("https://"):
        raise HTTPException(400, "Only http:// and https:// URLs allowed")
    from urllib.parse import urlparse
    parsed = urlparse(url)
    if not parsed.hostname or not _IP_RE.match(parsed.hostname):
        raise HTTPException(400, "Only IP-based URLs allowed")
    try:
        import ssl
        # PDC commonly uses self-signed certs; use a permissive HTTPS context so
        # redirects from http -> https can still be evaluated as reachable.
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        req = urllib.request.Request(url, method="GET")
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
        with opener.open(req, timeout=4) as resp:
            return {"url": url, "reachable": True, "status_code": resp.status}
    except urllib.error.HTTPError as err:
        # HTTPError still means the target host answered (e.g. 401 auth required).
        return {"url": url, "reachable": True, "status_code": err.code}
    except (urllib.error.URLError, OSError, TimeoutError):
        return {"url": url, "reachable": False, "status_code": None}
