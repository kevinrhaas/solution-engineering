"""
Migrate API — Content, datasource, and home-directory migration between Pentaho servers.

All endpoints invoke the existing shell scripts from pdc-analysis/utility/.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import re

from ..config import MIGRATE_SCRIPTS_DIR, DEPLOY_SCRIPTS_DIR, PENTAHO_CONTENT_DIR
from ..runner import runner

router = APIRouter(prefix="/api/migrate", tags=["migrate"])


def _server_ip(server_url: str) -> str:
    """Strip http(s):// and trailing slash from a server URL → host:port."""
    return re.sub(r'^https?://', '', server_url).rstrip('/')


def _server_dir(server_url: str) -> str:
    """Sanitize a server URL into a safe directory name, e.g. 10.0.0.1:80 → 10.0.0.1-80."""
    return re.sub(r'[^a-zA-Z0-9._-]', '-', _server_ip(server_url)).strip('-')


def _script(name: str):
    path = MIGRATE_SCRIPTS_DIR / name
    if not path.exists():
        raise HTTPException(500, f"Script not found: {name}")
    return path


def _deploy_script(name: str):
    path = DEPLOY_SCRIPTS_DIR / name
    if not path.exists():
        raise HTTPException(500, f"Script not found: {name}")
    return path


def _validate_env_filename(value: str, label: str) -> str:
    v = (value or "").strip()
    if not v:
        raise HTTPException(400, f"{label} is required")
    if "/" in v or ".." in v:
        raise HTTPException(400, f"Invalid {label}: path separators are not allowed")
    if not re.match(r"^[A-Za-z0-9._-]+\.env$", v):
        raise HTTPException(400, f"Invalid {label}: must look like <name>.env")
    return v


class MigrateFullRequest(BaseModel):
    source_url: str       # e.g. http://10.80.230.123:80
    target_url: str       # e.g. http://10.80.230.225:80
    source_user: str = "admin"
    source_pass: str = "password"
    target_user: str = "admin"
    target_pass: str = "password"
    dry_run: bool = False
    skip_home: bool = False
    skip_content: bool = False
    skip_ds: bool = False


class ContentRequest(BaseModel):
    server_url: str
    user: str = "admin"
    password: str = "password"
    path: str = "/public"  # repo path


class DatasourceRequest(BaseModel):
    server_url: str
    user: str = "admin"
    password: str = "password"


class HomeRequest(BaseModel):
    server_url: str
    user: str = "admin"
    password: str = "password"


class CubeRequest(BaseModel):
    server_url: str
    user: str = "admin"
    password: str = "password"
    schema_file: str
    datasource_name: str
    catalog_name: Optional[str] = None


class PdcMigrateRequest(BaseModel):
    source_ip: str
    target_ip: str
    source_env_file: str
    target_env_file: Optional[str] = None
    source_user: Optional[str] = None
    target_user: Optional[str] = None
    dry_run: bool = False
    stop_source: bool = False


# ── Full migration ───────────────────────────────────────────────────────────

@router.post("/full")
def full_migration(req: MigrateFullRequest):
    """Run a full server-to-server migration."""
    # migrate-server.sh expects host:port (no http://), flags before positional args,
    # and a single set of credentials used for both source pull and target push.
    flags = []
    if req.dry_run:
        flags.append("--dry-run")
    if req.skip_home:
        flags.append("--skip-home")
    if req.skip_content:
        flags.append("--skip-content")
    if req.skip_ds:
        flags.append("--skip-ds")
    args = flags + [
        _server_ip(req.source_url),
        _server_ip(req.target_url),
        req.source_user,
        req.source_pass,
    ]

    job = runner.start(
        script=_script("migrate-server.sh"),
        args=args,
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/pdc/full")
def pdc_full_migration(req: PdcMigrateRequest):
    """Run a full PDC migration using 40-migrate-pdc.sh."""
    source_env = _validate_env_filename(req.source_env_file, "source_env_file")
    target_env = _validate_env_filename(req.target_env_file or req.source_env_file, "target_env_file")

    args = [
        source_env,
        target_env,
        "--source-ip", req.source_ip,
        "--target-ip", req.target_ip,
    ]

    if req.source_user:
        args.extend(["--source-user", req.source_user])
    if req.target_user:
        args.extend(["--target-user", req.target_user])
    if req.stop_source:
        args.append("--stop-source")
    if req.dry_run:
        args.append("--dry-run")

    job = runner.start(
        script=_deploy_script("40-migrate-pdc.sh"),
        args=args,
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


# ── Content ──────────────────────────────────────────────────────────────────

@router.post("/content/pull")
def pull_content(req: ContentRequest):
    """Download /public content from a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "content"
    job = runner.start(
        script=_script("pull-content.sh"),
        args=[str(local_dir), req.path, server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/content/push")
def push_content(req: ContentRequest):
    """Upload local content to a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "content"
    job = runner.start(
        script=_script("push-content.sh"),
        args=[str(local_dir), req.path, server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


# ── Datasources ──────────────────────────────────────────────────────────────

@router.post("/datasources/pull")
def pull_datasources(req: DatasourceRequest):
    """Download all datasource definitions from a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "datasources"
    job = runner.start(
        script=_script("pull-datasources.sh"),
        args=[str(local_dir), server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/datasources/push")
def push_datasources(req: DatasourceRequest):
    """Upload all datasource definitions to a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "datasources"
    job = runner.start(
        script=_script("push-datasources.sh"),
        args=[str(local_dir), server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


# ── Home files ───────────────────────────────────────────────────────────────

@router.post("/home/pull")
def pull_home(req: HomeRequest):
    """Download /home content from a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "home"
    job = runner.start(
        script=_script("pull-home-files.sh"),
        args=[str(local_dir), "/home", server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/home/push")
def push_home(req: HomeRequest):
    """Upload /home content to a Pentaho server."""
    server_ip = _server_ip(req.server_url)
    local_dir = PENTAHO_CONTENT_DIR / _server_dir(req.server_url) / "home"
    job = runner.start(
        script=_script("push-home-files.sh"),
        args=[str(local_dir), server_ip, req.user, req.password],
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


# ── Mondrian cube ────────────────────────────────────────────────────────────

@router.post("/cube/publish")
def publish_cube(req: CubeRequest):
    """Publish a Mondrian schema to a Pentaho server."""
    args = [req.server_url, req.user, req.password,
            req.schema_file, req.datasource_name]
    if req.catalog_name:
        args.append(req.catalog_name)

    job = runner.start(
        script=_script("push-cube.sh"),
        args=args,
        cwd=MIGRATE_SCRIPTS_DIR,
    )
    return {"job_id": job.id}
