"""
Config API — SSH key management, AWS credential sync, git sync, and app restart.
"""

from __future__ import annotations
import json
import logging
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import urllib.request

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..config import WORKSPACE_ROOT
from ..db.engine import get_db
from ..db.crypto import encrypt, decrypt
from ..db.models import Secret, Profile, Instance, JobRecord, AppSetting

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/config", tags=["config"])


# ── DB secret helpers ─────────────────────────────────────────────────────────

def _store_secret(kind: str, name: str, plaintext: str, meta: dict | None = None) -> None:
    """Upsert an encrypted secret into the DB."""
    try:
        value = encrypt(plaintext)
        meta_str = json.dumps(meta or {})
        with get_db() as db:
            rec = db.query(Secret).filter_by(kind=kind, name=name).first()
            if rec is None:
                db.add(Secret(kind=kind, name=name, value_enc=value, meta_json=meta_str))
            else:
                rec.value_enc = value
                rec.meta_json = meta_str
                rec.updated_at = datetime.utcnow()
    except Exception:
        logger.exception("Could not store secret kind=%s name=%s in DB", kind, name)


def _delete_secret(kind: str, name: str) -> None:
    """Remove a secret from the DB (no error if not found)."""
    try:
        with get_db() as db:
            db.query(Secret).filter_by(kind=kind, name=name).delete()
    except Exception:
        logger.exception("Could not delete secret kind=%s name=%s from DB", kind, name)


def _purge_secrets(kind: str) -> None:
    """Remove all secrets of a given kind from the DB."""
    try:
        with get_db() as db:
            db.query(Secret).filter_by(kind=kind).delete()
    except Exception:
        logger.exception("Could not purge secrets kind=%s from DB", kind)


# ── SSH Key Management ───────────────────────────────────────────────────────

_SAFE_KEYNAME = re.compile(r'^[\w.+@_-]+\.pem$')


class SshKeyPaste(BaseModel):
    filename: str
    content: str


@router.post("/ssh-key")
def upload_ssh_key(body: SshKeyPaste):
    """Upload an SSH private key to ~/.ssh/ on the server."""
    filename = body.filename.strip()
    if not _SAFE_KEYNAME.match(filename):
        raise HTTPException(400, "Invalid key filename. Must end in .pem and contain only safe characters.")

    content = body.content.strip()
    if "PRIVATE KEY" not in content:
        raise HTTPException(400, "Does not look like a PEM private key (missing PRIVATE KEY header).")

    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)

    key_path = ssh_dir / filename
    key_path.write_text(content + "\n")
    key_path.chmod(0o600)

    _store_secret("ssh_key", filename, content)

    return {"status": "uploaded", "path": str(key_path)}


@router.delete("/ssh-key/{filename}")
def delete_ssh_key(filename: str):
    """Delete a single SSH key (.pem) from ~/.ssh/."""
    if not _SAFE_KEYNAME.match(filename):
        raise HTTPException(400, "Invalid key filename.")
    ssh_dir = Path.home() / ".ssh"
    key_path = ssh_dir / filename
    if not key_path.exists() or not key_path.is_file():
        raise HTTPException(404, f"SSH key not found: {filename}")
    key_path.unlink()
    _delete_secret("ssh_key", filename)
    return {"status": "deleted", "filename": filename}


@router.delete("/ssh-key")
def purge_ssh_keys():
    """Delete all .pem SSH keys from ~/.ssh/."""
    ssh_dir = Path.home() / ".ssh"
    removed = []
    if ssh_dir.exists():
        for f in ssh_dir.iterdir():
            if f.suffix == ".pem" and f.is_file():
                f.unlink()
                removed.append(f.name)
    _purge_secrets("ssh_key")
    return {"status": "purged", "removed": removed}


@router.get("/ssh-key/status")
def ssh_key_status():
    """List PEM keys in ~/.ssh/."""
    ssh_dir = Path.home() / ".ssh"
    if not ssh_dir.exists():
        return {"keys": []}

    keys = []
    for f in sorted(ssh_dir.iterdir()):
        if f.suffix == ".pem" and f.is_file():
            keys.append({"name": f.name, "size": f.stat().st_size})
    return {"keys": keys}


# ── AWS Credential Sync ──────────────────────────────────────────────────────

_SAFE_PROFILE = re.compile(r'^[A-Za-z0-9_-]+$')


class AwsCredentialsPaste(BaseModel):
    raw: str
    region: str = "us-east-1"


class AwsProfileVerifyRequest(BaseModel):
    profile: str


@router.post("/aws-credentials")
def sync_aws_credentials(body: AwsCredentialsPaste):
    """Parse pasted AWS credentials (INI, env-export, or JSON) and write to ~/.aws/."""
    parsed = _parse_credential_paste(body.raw)
    if not parsed:
        raise HTTPException(400, "Could not parse credentials. Paste INI format from ~/.aws/credentials, env exports, or JSON.")

    aws_dir = Path.home() / ".aws"
    aws_dir.mkdir(mode=0o700, exist_ok=True)

    # Merge into existing credentials
    creds_path = aws_dir / "credentials"
    existing = {}
    if creds_path.exists():
        existing = _parse_ini_sections(creds_path.read_text())

    synced_profiles = []
    for profile_name, cred_dict in parsed.items():
        if not _SAFE_PROFILE.match(profile_name):
            continue
        existing[profile_name] = cred_dict
        synced_profiles.append(profile_name)

    creds_path.write_text(_render_ini(existing))
    creds_path.chmod(0o600)

    # Update config for each profile
    config_path = aws_dir / "config"
    config_sections = {}
    if config_path.exists():
        config_sections = _parse_ini_sections(config_path.read_text())

    for profile_name in synced_profiles:
        key = f"profile {profile_name}" if profile_name != "default" else "default"
        config_sections.setdefault(key, {})
        config_sections[key]["region"] = body.region
        config_sections[key]["output"] = "json"

    config_path.write_text(_render_ini(config_sections))
    config_path.chmod(0o600)

    # Persist to DB (store the raw INI section for each synced profile)
    for profile_name in synced_profiles:
        _store_secret(
            "aws_credentials",
            profile_name,
            _render_ini({profile_name: existing[profile_name]}),
            meta={"region": body.region},
        )

    return {"status": "synced", "profiles": synced_profiles, "region": body.region}


@router.delete("/aws-credentials")
def purge_aws_credentials():
    """Purge all AWS credentials and config from ~/.aws/."""
    aws_dir = Path.home() / ".aws"
    removed = []
    for name in ("credentials", "config"):
        p = aws_dir / name
        if p.exists():
            p.unlink()
            removed.append(name)
    _purge_secrets("aws_credentials")
    return {"status": "purged", "removed": removed}


@router.delete("/aws-credentials/{profile_name}")
def purge_aws_profile(profile_name: str):
    """Remove a single named AWS profile from ~/.aws/credentials and ~/.aws/config."""
    if not _SAFE_PROFILE.match(profile_name):
        raise HTTPException(400, "Invalid profile name.")
    aws_dir = Path.home() / ".aws"
    creds_path = aws_dir / "credentials"
    config_path = aws_dir / "config"
    removed_from = []
    if creds_path.exists():
        sections = _parse_ini_sections(creds_path.read_text())
        if profile_name in sections:
            del sections[profile_name]
            creds_path.write_text(_render_ini(sections))
            creds_path.chmod(0o600)
            removed_from.append("credentials")
    if config_path.exists():
        sections = _parse_ini_sections(config_path.read_text())
        key = f"profile {profile_name}" if profile_name != "default" else "default"
        if key in sections:
            del sections[key]
            config_path.write_text(_render_ini(sections))
            config_path.chmod(0o600)
            removed_from.append("config")
    if not removed_from:
        raise HTTPException(404, f"Profile not found: {profile_name}")
    _delete_secret("aws_credentials", profile_name)
    return {"status": "removed", "profile": profile_name, "removed_from": removed_from}


@router.get("/aws-credentials/status")
def aws_credentials_status():
    """Check if AWS credentials exist and are configured."""
    creds_path = Path.home() / ".aws" / "credentials"
    if not creds_path.exists():
        return {"configured": False, "profiles": []}

    sections = _parse_ini_sections(creds_path.read_text())
    profiles = []
    for name in sections:
        has_key = bool(sections[name].get("aws_access_key_id"))
        has_token = bool(sections[name].get("aws_session_token"))
        profiles.append({"name": name, "has_key": has_key, "has_session_token": has_token})

    return {"configured": len(profiles) > 0, "profiles": profiles}


@router.post("/aws-credentials/verify")
def verify_aws_profile(body: AwsProfileVerifyRequest):
    """Verify that a synced AWS profile can call sts get-caller-identity."""
    profile = body.profile.strip()
    if not _SAFE_PROFILE.match(profile):
        raise HTTPException(400, "Invalid profile name.")

    try:
        proc = subprocess.run(
            ["aws", "--profile", profile, "sts", "get-caller-identity"],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except FileNotFoundError as exc:
        raise HTTPException(500, "AWS CLI is not installed on the ops-console server.") from exc
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(504, f"Timed out verifying AWS profile {profile}.") from exc

    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "AWS CLI failed.").strip().splitlines()[-1]
        raise HTTPException(422, detail)

    try:
        identity = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise HTTPException(500, "Could not parse AWS STS output.") from exc

    return {
        "status": "ok",
        "profile": profile,
        "account": identity.get("Account", ""),
        "arn": identity.get("Arn", ""),
        "user_id": identity.get("UserId", ""),
    }


# ── Git Sync & App Restart ────────────────────────────────────────────────────

_GIT_CREDENTIALS_FILE = Path.home() / ".git-credentials"
_DEFAULT_GIT_SYNC_REPO = os.environ.get("OPS_GIT_SYNC_REPO", "kevinrhaas/solution-engineering")
_DEFAULT_GIT_SYNC_BRANCH = os.environ.get("OPS_GIT_SYNC_BRANCH", "main")


def _normalize_git_repo(repo: str) -> str:
    repo = repo.strip().strip("/")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise HTTPException(400, "Repository must be in owner/name format.")
    return repo


def _normalize_git_branch(branch: str) -> str:
    branch = branch.strip()
    if not branch:
        raise HTTPException(400, "Branch cannot be empty.")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", branch):
        raise HTTPException(400, "Branch contains unsupported characters.")
    return branch


def _get_app_setting(key: str, default: str) -> str:
    try:
        with get_db() as db:
            rec = db.query(AppSetting).filter_by(key=key).first()
            if rec and rec.value:
                return rec.value
    except Exception:
        logger.exception("Could not load app setting %s", key)
    return default


def _set_app_setting(key: str, value: str) -> None:
    try:
        with get_db() as db:
            rec = db.query(AppSetting).filter_by(key=key).first()
            if rec is None:
                db.add(AppSetting(key=key, value=value))
            else:
                rec.value = value
                rec.updated_at = datetime.utcnow()
    except Exception as exc:
        logger.exception("Could not save app setting %s", key)
        raise HTTPException(500, f"Could not save setting {key}.") from exc


def _get_git_sync_source() -> dict[str, str]:
    repo = _normalize_git_repo(_get_app_setting("git_sync_repo", _DEFAULT_GIT_SYNC_REPO))
    branch = _normalize_git_branch(_get_app_setting("git_sync_branch", _DEFAULT_GIT_SYNC_BRANCH))
    return {
        "repo": repo,
        "branch": branch,
        "url": f"https://github.com/{repo}.git",
    }


def _check_github_token(token: str) -> dict:
    """Validate a token against the GitHub API. Returns {'ok': True} or {'ok': False, 'reason': '...'}"""
    git_source = _get_git_sync_source()
    target_repo = git_source["repo"]
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
    # Check if token is valid at all
    try:
        req = urllib.request.Request("https://api.github.com/user", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            user = json.loads(resp.read())["login"]
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return {"ok": False, "reason": "Token is invalid or expired."}
        return {"ok": False, "reason": f"GitHub API error {e.code} checking token."}
    except Exception as e:
        return {"ok": False, "reason": f"Could not reach GitHub API: {e}"}

    # Check if token can access the target repo
    try:
        req = urllib.request.Request(f"https://api.github.com/repos/{target_repo}", headers=headers)
        urllib.request.urlopen(req, timeout=10)
        return {"ok": True, "user": user}
    except urllib.error.HTTPError as e:
        if e.code in (404, 403):
            return {
                "ok": False,
                "reason": (
                    f"Token is valid (user: {user}) but cannot access {target_repo}. "
                    "For a fine-grained PAT, make sure the token is scoped to the "
                    f"{target_repo} repository with Contents read access. "
                    "For a classic PAT, enable the 'repo' scope and authorize it for the target org via SSO if required."
                ),
            }
        return {"ok": False, "reason": f"GitHub API error {e.code} checking repo access."}
    except Exception as e:
        return {"ok": False, "reason": f"Could not verify repo access: {e}"}


class GitTokenBody(BaseModel):
    token: str


class GitSourceBody(BaseModel):
    repo: str
    branch: str = _DEFAULT_GIT_SYNC_BRANCH


@router.post("/github-token")
def save_github_token(body: GitTokenBody):
    """Validate and save a GitHub Personal Access Token for HTTPS git auth."""
    token = body.token.strip()
    if not token:
        raise HTTPException(400, "Token cannot be empty.")

    # Validate the token before saving
    check = _check_github_token(token)
    if not check["ok"]:
        raise HTTPException(422, check["reason"])

    # Write to ~/.git-credentials in the standard format
    cred_line = f"https://x-access-token:{token}@github.com\n"
    _GIT_CREDENTIALS_FILE.write_text(cred_line)
    _GIT_CREDENTIALS_FILE.chmod(0o600)

    # Configure git to use credential store
    subprocess.run(
        ["git", "config", "--global", "credential.helper", "store"],
        cwd=str(WORKSPACE_ROOT), timeout=5, check=False,
    )

    # Persist token in DB so it survives git reset --hard
    _store_secret("git_token", "default", token, meta={"user": check.get("user", "")})

    return {"status": "saved", "user": check.get("user", "")}


@router.get("/github-token/status")
def github_token_status():
    """Check if a GitHub token is configured (file or DB)."""
    file_ok = _GIT_CREDENTIALS_FILE.exists() and _GIT_CREDENTIALS_FILE.stat().st_size > 0
    if file_ok:
        return {"configured": True}
    # Check DB as fallback
    try:
        with get_db() as db:
            rec = db.query(Secret).filter_by(kind="git_token", name="default").first()
        if rec:
            # Re-materialize the file from DB
            token = decrypt(rec.value_enc)
            cred_line = f"https://x-access-token:{token}@github.com\n"
            _GIT_CREDENTIALS_FILE.write_text(cred_line)
            _GIT_CREDENTIALS_FILE.chmod(0o600)
            subprocess.run(
                ["git", "config", "--global", "credential.helper", "store"],
                cwd=str(WORKSPACE_ROOT), timeout=5, check=False,
            )
            return {"configured": True}
    except Exception:
        logger.exception("Could not check git token in DB")
    return {"configured": False}


@router.delete("/github-token")
def delete_github_token():
    """Remove the saved GitHub token from ~/.git-credentials."""
    if _GIT_CREDENTIALS_FILE.exists():
        _GIT_CREDENTIALS_FILE.unlink()
    _delete_secret("git_token", "default")
    return {"status": "deleted"}


@router.get("/git/source")
def git_source():
    """Get the configured GitHub repo and branch used for app sync."""
    return _get_git_sync_source()


@router.put("/git/source")
def save_git_source(body: GitSourceBody):
    """Update the GitHub repo and branch used for app sync."""
    repo = _normalize_git_repo(body.repo)
    branch = _normalize_git_branch(body.branch)
    _set_app_setting("git_sync_repo", repo)
    _set_app_setting("git_sync_branch", branch)
    return {
        "status": "saved",
        "repo": repo,
        "branch": branch,
        "url": f"https://github.com/{repo}.git",
    }


@router.get("/git/status")
def git_status():
    """Get current git branch, commit, and dirty status."""
    git_source = _get_git_sync_source()
    # Check if workspace is a git repo
    if not (WORKSPACE_ROOT / ".git").exists():
        return {
            "branch": "n/a",
            "commit": "n/a",
            "commit_message": "Not a git repository — run deploy script to initialize",
            "dirty": False,
            "source_repo": git_source["repo"],
            "source_branch": git_source["branch"],
            "source_url": git_source["url"],
        }
    try:
        branch = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(WORKSPACE_ROOT), text=True, timeout=10,
        ).strip()
        commit = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=str(WORKSPACE_ROOT), text=True, timeout=10,
        ).strip()
        commit_msg = subprocess.check_output(
            ["git", "log", "-1", "--pretty=%s"],
            cwd=str(WORKSPACE_ROOT), text=True, timeout=10,
        ).strip()
        dirty = subprocess.call(
            ["git", "diff", "--quiet"],
            cwd=str(WORKSPACE_ROOT), timeout=10,
        ) != 0
        return {
            "branch": branch,
            "commit": commit,
            "commit_message": commit_msg,
            "dirty": dirty,
            "source_repo": git_source["repo"],
            "source_branch": git_source["branch"],
            "source_url": git_source["url"],
        }
    except Exception:
        # Git repo exists but may have no commits yet (freshly initialized)
        return {
            "branch": "main",
            "commit": "n/a",
            "commit_message": "Git initialized — configure a GitHub token in Config to enable self-updates",
            "dirty": False,
            "source_repo": git_source["repo"],
            "source_branch": git_source["branch"],
            "source_url": git_source["url"],
        }


class SyncRequest(BaseModel):
    dry_run: bool = False


def _schedule_service_restart() -> None:
    """Restart the service after the HTTP response has a chance to flush."""
    subprocess.Popen(
        [
            "/bin/sh",
            "-c",
            "(sleep 1; sudo systemctl restart pentaho-ops-console) "
            ">/tmp/pentaho-ops-console-restart.log 2>&1 &",
        ],
        start_new_session=True,
    )


@router.post("/sync")
def sync_app(body: SyncRequest):
    """Pull latest code from git, rebuild UI, and optionally restart the service."""
    results = []
    git_source = _get_git_sync_source()

    # Step 1: git fetch + reset
    try:
        fetch_out = subprocess.check_output(
            ["git", "fetch", "--depth", "1", git_source["url"], git_source["branch"]],
            cwd=str(WORKSPACE_ROOT), text=True, stderr=subprocess.STDOUT, timeout=30,
        ).strip()
        subprocess.check_output(
            ["git", "reset", "--hard", "FETCH_HEAD"],
            cwd=str(WORKSPACE_ROOT), text=True, stderr=subprocess.STDOUT, timeout=10,
        )
        results.append({
            "step": "git fetch",
            "ok": True,
            "output": fetch_out or f"Updated from {git_source['repo']}@{git_source['branch']}",
        })
    except subprocess.CalledProcessError as e:
        results.append({"step": "git fetch", "ok": False, "output": e.output.strip()})
        return {"dry_run": body.dry_run, "results": results, "restarted": False}

    # Step 2: npm ci (install/update node dependencies)
    ui_dir = WORKSPACE_ROOT / "pentaho-ops-console" / "ui"
    try:
        ci_out = subprocess.check_output(
            ["npm", "ci", "--silent"],
            cwd=str(ui_dir), text=True, stderr=subprocess.STDOUT, timeout=120,
        ).strip()
        results.append({"step": "npm ci", "ok": True, "output": ci_out[-200:] if len(ci_out) > 200 else (ci_out or "up to date")})
    except subprocess.CalledProcessError as e:
        results.append({"step": "npm ci", "ok": False, "output": e.output.strip()[-200:]})

    # Step 3: rebuild UI
    try:
        build_out = subprocess.check_output(
            ["npm", "run", "build"],
            cwd=str(ui_dir), text=True, stderr=subprocess.STDOUT, timeout=120,
        ).strip()
        results.append({"step": "npm build", "ok": True, "output": build_out[-500:] if len(build_out) > 500 else build_out})
    except subprocess.CalledProcessError as e:
        results.append({"step": "npm build", "ok": False, "output": e.output.strip()[-500:]})
        return {"dry_run": body.dry_run, "results": results, "restarted": False}

    # Step 4: pip install (in case requirements changed)
    app_dir = WORKSPACE_ROOT / "pentaho-ops-console"
    venv_pip = app_dir / "venv" / "bin" / "pip"
    if venv_pip.exists():
        try:
            pip_out = subprocess.check_output(
                [str(venv_pip), "install", "-q", "-r", str(app_dir / "requirements.txt")],
                cwd=str(app_dir), text=True, stderr=subprocess.STDOUT, timeout=60,
            ).strip()
            results.append({"step": "pip install", "ok": True, "output": pip_out[-200:] if len(pip_out) > 200 else (pip_out or "up to date")})
        except subprocess.CalledProcessError as e:
            results.append({"step": "pip install", "ok": False, "output": e.output.strip()[-200:]})

    if body.dry_run:
        results.append({"step": "restart", "ok": True, "output": "DRY RUN — skipped restart"})
        return {"dry_run": True, "results": results, "restarted": False}

    # Step 5: restart service
    try:
        _schedule_service_restart()
        results.append({"step": "restart", "ok": True, "output": "Service restart scheduled"})
    except Exception as e:
        results.append({"step": "restart", "ok": False, "output": str(e)})
        return {"dry_run": False, "results": results, "restarted": False}

    return {"dry_run": False, "results": results, "restarted": True}


@router.post("/restart")
def restart_app():
    """Restart the pentaho-ops-console systemd service."""
    try:
        _schedule_service_restart()
        return {"status": "restart scheduled"}
    except Exception as e:
        raise HTTPException(500, f"Restart failed: {e}")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _parse_credential_paste(raw: str) -> dict[str, dict[str, str]]:
    """Auto-detect and parse pasted credentials. Returns {profile: {key: val}}."""
    import json as _json
    text = raw.strip()

    # Try INI format (most common — straight from ~/.aws/credentials)
    if "[" in text:
        sections = _parse_ini_sections(text)
        if sections and any("aws_access_key_id" in v for v in sections.values()):
            return sections

    # Try env export format: export AWS_ACCESS_KEY_ID=AKIA...
    env_re = re.compile(r'(?:export\s+)?(\w+)\s*=\s*["\']?([^"\';\n]+)', re.MULTILINE)
    env_matches = dict(env_re.findall(text))
    if "AWS_ACCESS_KEY_ID" in env_matches:
        profile = env_matches.get("AWS_PROFILE", "default")
        cred = {"aws_access_key_id": env_matches["AWS_ACCESS_KEY_ID"]}
        if "AWS_SECRET_ACCESS_KEY" in env_matches:
            cred["aws_secret_access_key"] = env_matches["AWS_SECRET_ACCESS_KEY"]
        if "AWS_SESSION_TOKEN" in env_matches:
            cred["aws_session_token"] = env_matches["AWS_SESSION_TOKEN"]
        return {profile: cred}

    # Try JSON: {"AccessKeyId": "...", "SecretAccessKey": "...", ...}
    try:
        data = _json.loads(text)
        if isinstance(data, dict):
            creds_obj = data.get("Credentials", data)
            if "AccessKeyId" in creds_obj:
                return {"default": {
                    "aws_access_key_id": creds_obj["AccessKeyId"],
                    "aws_secret_access_key": creds_obj["SecretAccessKey"],
                    "aws_session_token": creds_obj.get("SessionToken", ""),
                }}
            if "aws_access_key_id" in creds_obj:
                return {"default": {
                    "aws_access_key_id": creds_obj["aws_access_key_id"],
                    "aws_secret_access_key": creds_obj.get("aws_secret_access_key", ""),
                    "aws_session_token": creds_obj.get("aws_session_token", ""),
                }}
    except (_json.JSONDecodeError, KeyError, TypeError):
        pass

    return {}


def _parse_ini_sections(text: str) -> dict[str, dict[str, str]]:
    """Minimal INI parser — returns {section_name: {key: value}}."""
    sections: dict[str, dict[str, str]] = {}
    current = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            sections.setdefault(current, {})
        elif "=" in line and current is not None:
            k, _, v = line.partition("=")
            sections[current][k.strip()] = v.strip()
    return sections


def _render_ini(sections: dict[str, dict[str, str]]) -> str:
    """Render sections dict back to INI format."""
    lines = []
    for section, kvs in sections.items():
        lines.append(f"[{section}]")
        for k, v in kvs.items():
            lines.append(f"{k} = {v}")
        lines.append("")
    return "\n".join(lines)


# ── Export / Import ───────────────────────────────────────────────────────────

class ExportRequest(BaseModel):
    include: list[str] = ["profiles", "instances", "jobs", "secrets", "settings"]


@router.post("/export")
def export_data(body: ExportRequest):
    """Export application data as a JSON bundle."""
    bundle: dict = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "app_version": "0.1.0",
        "include": body.include,
    }

    with get_db() as db:
        if "profiles" in body.include:
            bundle["profiles"] = [
                {
                    "id": p.id, "name": p.name, "server_type": p.server_type,
                    "raw_env": p.raw_env,
                    "created_at": p.created_at.isoformat() if p.created_at else None,
                }
                for p in db.query(Profile).all()
            ]

        if "instances" in body.include:
            bundle["instances"] = [
                {
                    "id": i.id, "name": i.name, "profile_name": i.profile_name,
                    "state_file": i.state_file, "ec2_instance_id": i.ec2_instance_id,
                    "instance_ip": i.instance_ip, "public_ip": i.public_ip,
                    "instance_state": i.instance_state, "deploy_phase": i.deploy_phase,
                    "server_type": i.server_type, "pentaho_version": i.pentaho_version,
                    "pdc_version": i.pdc_version, "instance_type": i.instance_type,
                    "environment": i.environment, "db_type": i.db_type,
                    "server_url": i.server_url, "created_date": i.created_date,
                    "raw_state": i.raw_state,
                }
                for i in db.query(Instance).all()
            ]

        if "jobs" in body.include:
            bundle["jobs"] = [
                {
                    "id": j.id, "script": j.script, "args": json.loads(j.args_json or "[]"),
                    "cwd": j.cwd, "status": j.status, "exit_code": j.exit_code,
                    "started_at": j.started_at, "finished_at": j.finished_at,
                    "created_at": j.created_at.isoformat() if j.created_at else None,
                }
                for j in db.query(JobRecord).order_by(JobRecord.created_at.desc()).limit(500).all()
            ]

        if "secrets" in body.include:
            # Export secrets with decrypted values (the bundle itself is the sensitive artifact)
            bundle["secrets"] = [
                {
                    "kind": s.kind, "name": s.name,
                    "value": decrypt(s.value_enc),
                    "meta": json.loads(s.meta_json or "{}"),
                }
                for s in db.query(Secret).all()
            ]

        if "settings" in body.include:
            bundle["settings"] = [
                {"key": s.key, "value": s.value}
                for s in db.query(AppSetting).all()
            ]

    return bundle


class ImportRequest(BaseModel):
    bundle: dict
    strategy: str = "merge"  # "merge" | "overwrite"


@router.post("/import")
def import_data(body: ImportRequest):
    """Import a previously exported data bundle."""
    bundle = body.bundle
    strategy = body.strategy
    stats: dict[str, int] = {}

    with get_db() as db:
        if "profiles" in bundle:
            count = 0
            for p in bundle["profiles"]:
                name = p.get("name", "")
                if not name:
                    continue
                existing = db.query(Profile).filter_by(name=name).first()
                if existing is None:
                    db.add(Profile(
                        id=p.get("id", None) or None,
                        name=name,
                        server_type=p.get("server_type", ""),
                        raw_env=p.get("raw_env", ""),
                    ))
                    count += 1
                elif strategy == "overwrite":
                    existing.server_type = p.get("server_type", existing.server_type)
                    existing.raw_env = p.get("raw_env", existing.raw_env)
                    existing.updated_at = datetime.utcnow()
                    count += 1
            stats["profiles"] = count

        if "instances" in bundle:
            count = 0
            for inst in bundle["instances"]:
                sf = inst.get("state_file", "")
                if not sf:
                    continue
                existing = db.query(Instance).filter_by(state_file=sf).first()
                if existing is None:
                    db.add(Instance(
                        name=inst.get("name", sf),
                        profile_name=inst.get("profile_name", ""),
                        state_file=sf,
                        ec2_instance_id=inst.get("ec2_instance_id", ""),
                        instance_ip=inst.get("instance_ip", ""),
                        public_ip=inst.get("public_ip", ""),
                        instance_state=inst.get("instance_state", ""),
                        deploy_phase=inst.get("deploy_phase", ""),
                        server_type=inst.get("server_type", ""),
                        pentaho_version=inst.get("pentaho_version", ""),
                        pdc_version=inst.get("pdc_version", ""),
                        instance_type=inst.get("instance_type", ""),
                        environment=inst.get("environment", ""),
                        db_type=inst.get("db_type", ""),
                        server_url=inst.get("server_url", ""),
                        created_date=inst.get("created_date", ""),
                        raw_state=inst.get("raw_state", ""),
                    ))
                    count += 1
                elif strategy == "overwrite":
                    existing.raw_state = inst.get("raw_state", existing.raw_state)
                    existing.instance_state = inst.get("instance_state", existing.instance_state)
                    existing.deploy_phase = inst.get("deploy_phase", existing.deploy_phase)
                    existing.server_url = inst.get("server_url", existing.server_url)
                    count += 1
            stats["instances"] = count

        if "secrets" in bundle:
            count = 0
            for s in bundle["secrets"]:
                kind = s.get("kind", "")
                name = s.get("name", "")
                value = s.get("value", "")
                if not kind or not value:
                    continue
                existing = db.query(Secret).filter_by(kind=kind, name=name).first()
                if existing is None:
                    db.add(Secret(
                        kind=kind, name=name,
                        value_enc=encrypt(value),
                        meta_json=json.dumps(s.get("meta", {})),
                    ))
                    count += 1
                elif strategy == "overwrite":
                    existing.value_enc = encrypt(value)
                    existing.meta_json = json.dumps(s.get("meta", {}))
                    existing.updated_at = datetime.utcnow()
                    count += 1
            stats["secrets"] = count

        if "settings" in bundle:
            count = 0
            for s in bundle["settings"]:
                key = s.get("key", "")
                if not key:
                    continue
                existing = db.query(AppSetting).filter_by(key=key).first()
                if existing is None:
                    db.add(AppSetting(key=key, value=s.get("value", "")))
                    count += 1
                elif strategy == "overwrite":
                    existing.value = s.get("value", existing.value)
                    existing.updated_at = datetime.utcnow()
                    count += 1
            stats["settings"] = count

    return {"status": "imported", "strategy": strategy, "stats": stats}
